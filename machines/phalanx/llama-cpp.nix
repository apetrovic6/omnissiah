# llama.cpp — the other local inference endpoint, as an alternative to
# ./vllm.nix. Run one or the other; both default to port 8000 and both want the
# same VRAM, so they are not meant to be up at the same time.
#
# Why this exists alongside the vLLM container: llama.cpp is a native NixOS
# module (no container, no `broken = cudaSupport` gate) and, more importantly,
# its multi-GPU split can be ASYMMETRIC. vLLM's tensor parallelism allocates the
# same budget to every rank, so GPU0 -- which drives DP-2 and already holds
# ~3.4GB for niri and browsers -- caps both cards at ~6GB, giving ~12GB usable.
# `--tensor-split` here lets the display card carry less:
#
#   GPU0  0000:0b:00.0  ~6.0GB  (shares with the desktop)
#   GPU1  0000:0c:00.0  ~9.5GB  (idle otherwise)
#                       ------
#                       ~15.5GB usable
#
# That extra headroom, plus GGUF's finer quant steps (Q3_K, IQ4_XS) versus AWQ's
# fixed 4-bit, is what brings a 30B-A3B checkpoint back into range.
#
# Cost versus the container: this builds llama.cpp against CUDA locally (~17
# derivations, ~690MB of CUDA fetched) and rebuilds on every nixpkgs bump that
# touches the CUDA stack.
{
  config,
  lib,
  pkgs,
  ...
}: let
  port = 8000;

  # Models live in the user's home so they can be fetched and swapped without
  # sudo, persisted by the "models" entry in users.apetrovic.directories
  # (modules/rites/impermanence.nix) -- /home/apetrovic/models is bind-mounted
  # from /persist/home/apetrovic/models and survives the boot rollback.
  #
  # The service cannot read that path directly, for two independent reasons:
  # the unit sets ProtectHome=true, which makes /home appear EMPTY inside its
  # namespace, and /home/apetrovic is mode 0700, which a DynamicUser=true
  # service (unstable UID, its own group) cannot traverse anyway. Relaxing
  # ProtectHome alone does not fix the second problem.
  #
  # BindReadOnlyPaths solves both: systemd performs the mount as root before
  # dropping privileges, so the 0700 parent is irrelevant, and the destination
  # sits outside /home where ProtectHome does not apply. The service sees the
  # directory read-only at sandboxModelsDir; the .gguf files themselves still
  # need to be world-readable (0644, which is what a normal umask gives).
  hostModelsDir = "/home/apetrovic/models";
  sandboxModelsDir = "/models";

  # Confirm the exact asset name on HF before committing to it -- quant filename
  # conventions vary by publisher. Fetch it as yourself, no sudo needed:
  #   nix shell nixpkgs#python3Packages.huggingface-hub -c \
  #     hf download <repo> <file> --local-dir ~/models
  # The command is `hf`; the older `huggingface-cli` still ships in the same
  # package but is deprecated and now refuses to run.
  # Do NOT use llama-server's own -hf downloader here: it caches into
  # CacheDirectory (/var/cache/llama-cpp), which the boot rollback wipes.
  modelFile = "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf";
in {
  services.llama-cpp = {
    enable = true;
    package = pkgs.llama-cpp.override {cudaSupport = true;};

    settings = {
      model = "${sandboxModelsDir}/${modelFile}";
      host = "127.0.0.1";
      inherit port;

      # Asymmetric split, the whole reason to prefer this over vLLM on this
      # machine. Ratio, not gigabytes: ~6/16 to GPU0, ~10/16 to GPU1.
      tensor-split = "6,10";

      # "layer" distributes whole layers: capacity adds up but only one GPU
      # computes at a time, so decode is roughly single-GPU speed. "row" splits
      # each tensor by rows so both cards work in parallel, at the cost of a
      # sync every layer -- over PCIe 4.0 x8 with no NVLink that can be a wash
      # or worse on a 3B-active MoE. Measure both before assuming row wins.
      split-mode = "layer";

      n-gpu-layers = 999;

      # Total KV pool, DIVIDED across the parallel slots below -- not per slot.
      ctx-size = 32768;

      # Concurrent request slots. 1 means a second caller blocks until the first
      # finishes. Raise it to fan out subagents from opencode/herdr, but
      # remember each slot gets ctx-size/parallel: 4 slots here is 8K each,
      # which is thin for agent work. vLLM's continuous batching handles this
      # case better if fan-out turns out to matter more than raw context.
      parallel = 1;

      # q8_0 KV roughly halves cache footprint against fp16 for negligible
      # quality loss, which is what makes 32K fit next to a ~14.7GB model.
      cache-type-k = "q8_0";
      cache-type-v = "q8_0";
      flash-attn = "on";

      # Required for tool calling: without it llama-server ignores the model's
      # chat template for tool-call formatting and opencode receives malformed
      # calls. This is the equivalent of vLLM's --tool-call-parser and it is not
      # on by default.
      jinja = true;

      # Stable alias so swapping modelFile does not mean editing
      # ~/.config/opencode/opencode.jsonc to match.
      alias = "local-coder";
    };
  };

  # Off by default, matching ./vllm.nix: the server pins its VRAM budget for as
  # long as it runs, which is the wrong standing trade on a workstation that
  # also drives a 4K display and games. Start it on demand:
  #   systemctl start llama-cpp
  systemd.services.llama-cpp = {
    wantedBy = lib.mkForce [];

    serviceConfig = {
      # Make ~/models visible inside the sandbox, read-only. Without this the
      # server dies with ENOENT on the model path: ProtectHome=true blanks
      # /home, and the 0700 home directory blocks the DynamicUser regardless.
      BindReadOnlyPaths = ["${hostModelsDir}:${sandboxModelsDir}"];

      # PrivateUsers=true puts the service in a user namespace. If the CUDA
      # backend reports no devices, relax this first, before suspecting the
      # driver -- PrivateDevices is already false upstream for GPU access.
      PrivateUsers = lib.mkDefault true;
    };
  };
}
