# llama-swap -- OpenAI-compatible proxy that owns the llama-server processes and
# swaps models on demand. Supersedes ./llama-cpp.nix (left on disk, no longer
# imported): llama-swap spawns llama-server itself, so running both would only
# fight over port 8000 and VRAM.
#
# The `model` field in each request selects the model, so switching costs no
# restart or rebuild. Each model has an idle `ttl` after which it unloads and
# hands VRAM back to the desktop -- which is why this service, unlike
# ./vllm.nix, stays enabled at boot: the proxy costs nothing until called.
#
# VRAM is the binding constraint and the split is uneven, measured with
# `llama-server --list-devices`:
#   CUDA0 (0000:0b:00.0)  9873 MiB total  <- drives DP-2, desktop holds 2-5GB
#   CUDA1 (0000:0c:00.0)  9877 MiB total  <- idle
# Only one model is resident at a time; this does not hold two.
#
# The rule that decides whether a model is viable here: a DENSE model must fit
# entirely in VRAM, because every parameter is read per token and anything
# spilled to RAM streams over PCIe constantly. An MoE only touches its active
# experts and tolerates the spill. Devstral-24B (dense, 13.5GB) was measured at
# 3.7 tok/s decode against 67 for a 35B-A3B MoE of similar file size, and was
# dropped for it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # doCheck = false because nixpkgs enables the test suite unconditionally,
  # including for cudaSupport builds, and the sandbox has no GPU:
  #
  #   ggml_cuda_init: failed to initialize CUDA: CUDA driver is a stub library
  #   28 - test-recurrent-state-rollback (Timeout)
  #   29 - test-save-load-state (Timeout)
  #
  # Both fall back to CPU and walk ~100 model architectures, so they blow
  # ctest's 1500s per-test cap -- they cannot pass here, GPU or not. Upstream
  # already disables a sibling (test-state-restore-fragmented). This also sets
  # LLAMA_BUILD_TESTS false, so the test binaries are never compiled.
  llamaCpp = (pkgs.llama-cpp.override {cudaSupport = true;}).overrideAttrs {doCheck = false;};
  llamaServer = lib.getExe' llamaCpp "llama-server";

  # Models live in the user's home so they can be fetched without sudo,
  # persisted via the "models" entry in users.apetrovic.directories
  # (modules/rites/impermanence.nix). The service cannot read that path
  # directly -- ProtectHome=true blanks /home inside the namespace, and
  # /home/apetrovic is 0700, which a DynamicUser service cannot traverse.
  # BindReadOnlyPaths below mounts it somewhere visible; systemd does that as
  # root before dropping privileges, so 0700 is moot. Spawned llama-server
  # children inherit the namespace.
  hostModelsDir = "/home/apetrovic/models";
  sandboxModelsDir = "/models";

  # Flags every model shares. ''${PORT} is llama-swap's placeholder for the
  # upstream port it allocates -- escaped so Nix does not interpolate it.
  #
  # DELIBERATELY ABSENT: --n-gpu-layers, --tensor-split, --split-mode and
  # --n-cpu-moe. llama.cpp measures free VRAM per device at startup and fits
  # the layer assignment to it, but ONLY for arguments the user has not set:
  #
  #   common_fit_params: ... n_gpu_layers already set by user to 999, abort
  #   common_fit_params: ... tensor_buft_overrides already set by user, abort
  #
  # Either one turns a marginal model from "fits" into "OOMs", and raising the
  # value cannot help because any value disables the fitting. --n-cpu-moe looks
  # like the obvious lever for an oversized MoE and is the worst offender.
  # Reach for them only if you are willing to place everything by hand.
  #
  # What works instead, in order of preference:
  #   (nothing)   let auto-fit spill experts to RAM -- 125GB of it, and a
  #               low-active-param MoE is the best case for that spill.
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
      # Cold start here is over four minutes for the larger entries. Too low a
      # value marks the model unhealthy and kills it mid-load, which looks
      # exactly like a crash.
      healthCheckTimeout = 600;

      models = {
        # MoE, ~3B active, so decode is closer to a 3B than a 30B.
        # Measured: ~88 tok/s decode, ~990 tok/s prompt.
        "coder-30b" = mkModel {
          file = "qwen3-coder-30b-a3b-instruct-q3_k_m.gguf";
        };

        # 35B-A3B, 16.5GB of weights. Measured: ~960 tok/s prefill, 67 tok/s
        # decode. Hybrid attention -- only 10 of 40 layers are full attention
        # (full_attention_interval 4), each with 2 KV heads x 256, so KV is
        # ~11KB/token at q8_0 and long context is cheap. Native max 262144.
        #
        # Keep in sync with contextWindow in magos modules/features/pi/default.nix.
        "qwen36-35b-q4" = mkModel {
          file = "Qwen3.6-35B-A3B-UD-IQ4_XS.gguf";
          ctxSize = 131072;
        };

        # qwen4exp: 512 experts with 10 active, 3 of every 4 layers linear
        # attention. ~82GB across three shards -- the binding constraint is
        # system RAM, not VRAM. --model points at the FIRST shard and
        # llama.cpp loads the rest itself.
        #
        # If it ever crawls, check `free -g` before blaming the model:
        # llama.cpp mmaps the file, so experts that do not fit stay on disk and
        # are paged in from NVMe per token rather than failing cleanly.
        #
        # Only 12 of 48 layers are full attention, ~13KB/token at q8_0, so
        # 131072 costs ~1.7GB of KV. The real limit is prefill, not memory:
        # a full 128K prompt takes minutes. Prefix caching pays that once per
        # session, and again after every compaction.
        #
        # Keep in sync with contextWindow in magos modules/features/pi/default.nix.
        "qwen38-flash-q3" = mkModel {
          file = "UD-IQ3_XXS/Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf";
          ctxSize = 131072;

          # ttl 3600, not the 900 default: an idle unload costs a 4-minute cold
          # load PLUS a full re-prefill of the prefix cache. At 900 one thinking
          # pause crosses the line and pays all of it. Go to 0 (never unload) if
          # RAM pressure allows -- this entry alone holds ~57GB resident.
          ttl = 3600;

          # MTP speculative decoding is OFF -- it crashes on stock llama.cpp.
          # Do not re-add the flags below without re-running the two tests at
          # the end of this comment; both failures look like a dead model to
          # llama-swap, which reports only "upstream command exited
          # prematurely" and a 500 to the client. The real error is in the
          # per-model log (`curl localhost:8000/logs/stream/qwen38-flash-q3`),
          # never in `journalctl -u llama-swap`.
          #
          # qwen4exp MTP went upstream in ggml-org/llama.cpp#29761 (merged
          # 2026-10-01, in v0.6.0), superseding the unmerged #28243 that this
          # entry used to carry a danielhanchen fork for. The measurements
          # below were taken on that fork. On stock 0.6.0 neither of the two
          # MTP ggufs in ~/models/MTP works, for two different reasons:
          #
          #   mtp-...-shared-Q8_0.gguf  carries no token_embd.weight and no
          #     output.weight -- it was built to borrow both from the main
          #     model, which only the fork could do. Stock loads a draft as a
          #     standalone llama_model, so it dies at
          #     "check_tensor_dims: tensor 'token_embd.weight' not found".
          #
          #   mtp-...-Q8_0.gguf  has both tensors and gets past that, then
          #     aborts during the load-time probe decode:
          #       GGML_ASSERT(buffer) failed  (ggml-backend.cpp:345)
          #         <- llama_kv_cache::set_input_k_idxs
          #         <- llama_model_qwen4exp::llm_graph_input_kpool::set_input
          #     A null buffer on a graph input, inside qwen4exp's own hybrid-
          #     attention kpool path. Verified NOT to be a memory-fit problem:
          #     it aborts identically with --fit-target dropped entirely.
          #
          # So MTP needs an upstream fix, not a flag. Retry after a llama-cpp
          # bump by appending to this entry:
          #
          #   extraFlags = builtins.concatStringsSep " " [
          #     "-md ${sandboxModelsDir}/MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf"
          #     "--spec-type draft-mtp"
          #     "--spec-draft-n-max 2"
          #     "--fit-target 1024,4096"
          #   ];
          #
          # --fit-target 1024,4096 belongs with them and only with them:
          # auto-fit sizes the main model WITHOUT the draft ("failed to measure
          # the memory of the extra model, fitting without it"), fills both
          # GPUs, and the draft then OOMs on device 1. Reserving 4096 MiB there
          # leaves room for it. Unlike -ngl or --n-cpu-moe it is an INPUT to
          # auto-fit and does not disable it. With no draft it only wastes VRAM.
          #
          # Measured 2026-09-29 on the fork via /v1/chat/completions, temp 0,
          # warmup dropped, mean decode tok/s -- what MTP is worth if it is ever
          # fixed. Output was identical to no speculation (verified byte-for-
          # byte at temp 0); only speed changed.
          #
          #                       file-rewrite turn   reasoning turn
          #   no speculation           20.7               21.2
          #   MTP (fork)               24.7  (+19%)       21.5  (+1%)
          #   ngram-mod                18.7  (-10%)       16.2  (-24%)
          #
          # So the gain was concentrated in turns that reproduce text already in
          # context, and was nil when the model reasons from scratch. Two
          # settled questions, do not re-open without new evidence:
          #
          #   ngram-mod LOSES to no speculation at all. It drafts 48-64 tokens
          #   per step at ~26-76% acceptance, and every rejection costs a verify
          #   pass over a large batch. Tempting because it needs no draft model
          #   and would free the 2647 MiB that one costs, but it is slower.
          #
          #   --spec-draft-n-max 3 and 4 are not better than 2. Blended across
          #   both turn types: 23.45 / 22.73 / 23.37 tok/s for 2 / 3 / 4. The
          #   ordering flips by prompt, so there is no trend to chase. Deeper
          #   drafts mean bigger verify batches, and this box is prefill-weak --
          #   the same reason ngram-mod loses.
          #
          # NEVER set --ubatch-size on this entry. This model routes 10 of 512
          # experts per token, so the router's top_k argsort runs every layer
          # and its CUB workspace scales with ubatch x n_experts. That workspace
          # is a POOL allocation made during decode, not a buffer sized at load,
          # so it does not fail at startup -- the server loads clean, health
          # checks green, then aborts mid-reply:
          #
          #   ggml_cuda_pool_vmm::alloc -> argsort_f32_i32_cuda_cub
          #     -> ggml_cuda_op_top_k -> llama_context::decode -> ggml_abort
          #
          # --ubatch-size 1024 together with a reduced --fit-target did exactly
          # that (device 1 down to 69 MiB free). After any change here, load the
          # model and check `nvidia-smi` free memory on device 1: a few hundred
          # MiB or less means the next allocation kills it.
        };
      };
    };
  };

  # llama-swap shells out to nvidia-smi to report VRAM use in its web UI. NixOS
  # systemd units get a minimal PATH, so without this it logs "GPU monitoring
  # not available" and omits that panel. nvidia-smi lives in the driver
  # package's `bin` output, not `out`.
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
