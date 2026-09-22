# llama-swap — OpenAI-compatible proxy that owns the llama-server processes and
# swaps models on demand. Supersedes ./llama-cpp.nix (left on disk, no longer
# imported): llama-swap spawns llama-server itself, so running both would only
# fight over port 8000 and VRAM.
#
# What this buys over a fixed services.llama-cpp:
#   - The `model` field in each request selects the model. opencode asks for
#     "coder-30b" or "qwen3-14b" and the swap happens underneath -- no restart,
#     no rebuild, no editing this file to try a different quant.
#   - Per-model idle `ttl`: the model loads on first request and unloads itself
#     once idle, handing VRAM back to the desktop. That is why this service,
#     unlike ./vllm.nix, is left enabled at boot -- the proxy costs nothing
#     until someone actually calls it.
#
# VRAM is the binding constraint and the split is uneven, measured with
# `llama-server --list-devices` rather than estimated:
#   CUDA0 (0000:0b:00.0)  9873 MiB total, 5815 MiB free  <- drives DP-2
#   CUDA1 (0000:0c:00.0)  9877 MiB total, 9638 MiB free  <- idle
# ~15.1GiB free against a 13.7GiB model file, so the weights fit but little is
# left for KV cache. llama.cpp sizes the offload to that itself -- see the
# mkModel comment for why nothing here pins --n-gpu-layers or --tensor-split.
# Only one model is resident at a time; this does not hold two.
{
  config,
  lib,
  pkgs,
  ...
}: let
  llamaCpp = pkgs.llama-cpp.override {cudaSupport = true;};
  llamaServer = lib.getExe' llamaCpp "llama-server";

  # Same reasoning as ./llama-cpp.nix: models live in the user's home so they
  # can be fetched without sudo, persisted via the "models" entry in
  # users.apetrovic.directories (modules/rites/impermanence.nix). The service
  # cannot read that path directly -- ProtectHome=true blanks /home inside the
  # namespace, and /home/apetrovic is 0700, which a DynamicUser service cannot
  # traverse regardless. BindReadOnlyPaths below mounts it somewhere visible;
  # systemd does that as root, before dropping privileges, so 0700 is moot.
  # Spawned llama-server children inherit the namespace, so they see it too.
  hostModelsDir = "/home/apetrovic/models";
  sandboxModelsDir = "/models";

  # Flags every model shares. ''${PORT} is llama-swap's own placeholder for the
  # upstream port it allocates -- escaped so Nix does not interpolate it.
  # --no-webui because llama-swap serves its own UI in front.
  #
  # Deliberately absent: --n-gpu-layers, --tensor-split and --split-mode.
  # llama.cpp measures free VRAM per device at startup and fits the layer
  # assignment to it, but ONLY if the user has not pinned those itself. Setting
  # -ngl 999 disables that outright:
  #
  #   common_fit_params: failed to fit params to free device memory:
  #     n_gpu_layers already set by user to 999, abort
  #   ggml_backend_cuda_buffer_type_alloc_buffer: allocating 646.00 MiB on
  #     device 0: cudaMalloc failed: out of memory
  #   llama_init_from_model: failed to initialize the context: failed to
  #     allocate buffer for kv cache
  #
  # The weights fit; the KV cache is what ran out, on GPU0, because the desktop
  # holds ~4GB there (measured: CUDA0 5815 MiB free, CUDA1 9638 MiB free,
  # ~15.1GiB total against a 13.7GiB model). Auto-fit already knows GPU0 is the
  # smaller side, which is what the hand-written --tensor-split 6,10 was trying
  # to express, so it earns its keep better than a guessed ratio.
  #
  # Levers if a model still will not fit. NOTE that --n-cpu-moe is NOT one of
  # them, despite looking like the obvious tool: it sets tensor_buft_overrides,
  # which aborts auto-fit exactly the way -ngl does --
  #
  #   common_fit_params: failed to fit params to free device memory:
  #     model_params::tensor_buft_overrides already set by user, abort
  #   ggml_backend_cuda_buffer_type_alloc_buffer: allocating 148.30 MiB on
  #     device 1: cudaMalloc failed: out of memory
  #
  # so adding it makes a marginal model fail rather than fit, and raising the
  # value cannot help because any value disables the fitting. Reach for it only
  # if you are willing to place everything by hand, -ngl included.
  #
  # What does work, in order of preference:
  #   (nothing)   let auto-fit spill experts to RAM by itself -- there is 125GB
  #               of it, and a 3B-active MoE is the best case for that spill.
  #   ctxSize     KV cache scales with it; halving it is the bluntest fix.
  #   cache-type  already q8_0 below; q4_0 halves KV again at some quality cost.
  #   a smaller quant of the same weights.
  mkModel = {
    file,
    ctxSize ? 32768,
    parallel ? 1,
    ttl ? 900,
    extraFlags ? "",
  }: {
    # Seconds idle before the model is unloaded and the VRAM released. Confirm
    # the key against upstream's config.example.yaml if a release renames it;
    # `settings` is freeform, so a typo would pass through to YAML silently.
    inherit ttl;

    cmd = ''
      ${llamaServer} --port ''${PORT}
        --model ${sandboxModelsDir}/${file}
        --ctx-size ${toString ctxSize}
        --parallel ${toString parallel}
        --cache-type-k q8_0
        --cache-type-v q8_0
        --flash-attn on
        --jinja
        --no-webui
        ${extraFlags}
    '';
  };
in {
  services.llama-swap = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 8000;

    settings = {
      # A 13.7GB model is slow to load from cold page cache, and slower still
      # when auto-fit pushes MoE expert weights out to RAM. Too low a value
      # marks it unhealthy and kills it mid-load, which looks exactly like a
      # crash. Measured cold start here is over four minutes.
      healthCheckTimeout = 600;

      models = {
        # Primary agentic model. MoE with ~3B active params, so decode speed is
        # closer to a 3B than a 30B -- the reason it is worth the VRAM here.
        # Measured: ~88 tok/s decode, ~990 tok/s prompt.
        "coder-30b" = mkModel {
          file = "qwen3-coder-30b-a3b-instruct-q3_k_m.gguf";
        };

        # Newer generation, same 35B-A3B shape (3B active), so it should keep
        # the speed character of coder-30b. Two quants of the same weights,
        # because the interesting question is precision, not size:
        #
        #   coder-30b is Q3_K_M -- roughly the same bits/param as -q3 below, so
        #   comparing against -q3 isolates the architecture change, and against
        #   -q4 isolates quantization damage.
        #
        # 13.2GB, fits entirely in the ~15.1GiB of free VRAM alongside its KV
        # cache, the same way coder-30b does.
        "qwen36-35b-q3" = mkModel {
          file = "Qwen3.6-35B-A3B-UD-IQ3_XXS.gguf";
          # 32768 was too small: opencode died with "request (34169 tokens)
          # exceeds the available context size" on a routine devenv task, and
          # was running compaction before that. Reasoning models spend tokens
          # thinking on every turn, on top of tool schemas and file reads.
          # Verified 65536 AND 98304 both load even with only ~3GB of free
          # VRAM (auto-fit spills KV to RAM), so this is not the binding limit.
          ctxSize = 65536;
        };

        # 17.7GB, which does NOT fit -- ~2.6GB over, before KV cache. Rather
        # than leave that to auto-fit, push expert weights to RAM explicitly:
        # a 3B-active MoE is the best case for this, since only the active
        # experts are read per token and there is 125GB of RAM to spill into.
        #
        # 12 is a starting guess, NOT a measured value. Raise it if the load
        # OOMs, lower it while it still fits -- every layer left on the GPU is
        # decode speed. Watch `llama-server --list-devices` free memory, or the
        # VRAM panel in llama-swap's UI, on first load.
        "qwen36-35b-q4" = mkModel {
          file = "Qwen3.6-35B-A3B-UD-IQ4_XS.gguf";
          # Same reasoning as -q3. This one has less VRAM headroom (16.5GB
          # of weights), so more of the KV cache spills to RAM -- slower, but
          # it loads, and running out of context is worse than running slow.
          ctxSize = 65536;
          # extraFlags = "--n-cpu-moe 16";
        };

        # DISABLED -- does not fit this hardware. Measured with a 28k
        # prompt, cold, against the same prompt the other entries ran:
        #
        #   ctxSize 65536:  573 tok/s prefill, 2.8 tok/s decode
        #   ctxSize 32768:  778 tok/s prefill, 3.7 tok/s decode
        #   qwen36-35b-q4:  960 tok/s prefill,  67 tok/s decode
        #
        # It spills even at 32768: ~13.5GB of weights plus a dense
        # 40-layer full-attention KV cache does not fit in ~17.5GB of
        # VRAM with a desktop on GPU0. Being dense, EVERY param is read
        # per token, so spilled weights stream over PCIe constantly --
        # an MoE only touches its ~3B active params and shrugs it off.
        # An earlier 15 tok/s reading was measured on a 6-token prompt,
        # i.e. with the KV cache empty and the weights still resident;
        # it did not survive real context.
        #
        # Kept for reference. Re-enable only with a quant small enough
        # to stay fully in VRAM alongside its KV cache.
        # # Dense 24B, Apache 2.0, purpose-built with All Hands AI for agentic
        # # coding scaffolds. At 13.5GB it fits the same budget coder-30b uses at
        # # Q3_K_M, but at a higher effective quant -- this is the entry that
        # # tests whether Q3 quantization damage is what limits the 30B, rather
        # # than the model generation itself.
        # #
        # # Expect it to be markedly slower: 24B dense activates all 24B per
        # # token, against ~3B for the A3B models above. Quality-per-token versus
        # # tokens-per-second is the whole trade being measured here.
        # #
        # # Filename has no UD- prefix, unlike the Qwen quants -- unsloth only
        # # prefixes some of Devstral's. Verified against the HF file listing.
        # "devstral-24b" = mkModel {
        #   file = "Devstral-Small-2-24B-Instruct-2512-Q4_K_S.gguf";
        #   # 32768 on purpose, unlike the MoE entries. This model is DENSE, and
        #   # that changes the arithmetic completely:
        #   #
        #   #   - Full attention on every layer means a much larger KV cache than
        #   #     the Qwen MoEs need, so 65536 does not fit beside 13.5GB of
        #   #     weights in ~17.5GB of VRAM.
        #   #   - Every one of its 24B params is read per token, so any weight
        #   #     spilled to RAM is streamed over PCIe every token. An MoE only
        #   #     touches its ~3B active params and barely notices the spill.
        #   #
        #   # Measured at ctxSize 65536 with a 28k prompt: decode fell to 2.8
        #   # tok/s, against 15 tok/s at 32768. Raise this only if the weights
        #   # still fit entirely in VRAM afterwards.
        #   #
        #   # Keep in sync with limit.context in magos modules/features/opencode.nix.
        #   ctxSize = 32768;
        # };

        # New architecture (qwen4exp), not a bigger Qwen3.6: 512 experts with 10
        # active, and 3 of every 4 layers use linear attention, so the KV cache
        # stays small and long context is cheap. Support verified: the GGUF
        # declares general.architecture = qwen4exp and the deployed libllama has
        # qwen4exp.cpp compiled in.
        #
        # ~82GB across three shards -- the binding constraint is system RAM, not
        # VRAM. At the time of writing only ~63GB was free (125 total, 23.5GB
        # already in zram), so this sits right at the edge. It will NOT fail
        # cleanly if memory runs short: llama.cpp mmaps the file, so experts
        # that do not fit stay on disk and are paged in from NVMe per token.
        # It keeps answering, just drastically slower. If it crawls, check
        # `free -g` before blaming the model.
        #
        # Sharded: --model points at the FIRST shard, subdirectory included,
        # and llama.cpp loads -00002/-00003 itself. Filenames verified against
        # the HF listing and the partially downloaded directory.
        "qwen38-flash-q3" = mkModel {
          file = "UD-IQ3_XXS/Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf";
          ctxSize = 65536;
        };

        # Commented out, not deleted: the filename below was invented as a
        # placeholder and never corresponded to a real asset, so this entry
        # fails to load exactly like the case-mismatch did. Restore it with a
        # verified filename if a dense long-context fallback is still wanted --
        # the two 35B entries above now cover the same ground better.
        #
        # "qwen3-14b" = mkModel {
        #   file = "<verified-filename>.gguf";
        #   ctxSize = 65536;
        # };
      };
    };
  };

  # llama-swap shells out to nvidia-smi to report VRAM use in its web UI. NixOS
  # systemd units get a minimal PATH (coreutils, findutils, grep, sed, systemd),
  # so without this it logs "GPU monitoring not available: no GPU monitoring
  # tool available" and simply omits that panel -- cosmetic, but free to fix.
  # nvidia-smi lives in the driver package's `bin` output, not `out`.
  systemd.services.llama-swap.path = [config.hardware.nvidia.package.bin];

  systemd.services.llama-swap.serviceConfig = {
    # Without this every model fails with ENOENT on its --model path. See the
    # hostModelsDir comment above for why a plain path does not work.
    BindReadOnlyPaths = ["${hostModelsDir}:${sandboxModelsDir}"];

    # PrivateUsers=true puts the service in a user namespace. If the CUDA
    # backend reports no devices, relax this first, before suspecting the
    # driver -- PrivateDevices is already false upstream for GPU access.
    PrivateUsers = lib.mkDefault true;
  };
}
