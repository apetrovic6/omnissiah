# vLLM — OpenAI-compatible inference endpoint for the local coding model that
# opencode (and anything else herdr starts in a pane) points at.
#
# Why a container rather than a NixOS service: there is no `services.vllm`
# module in nixpkgs at all, and `pkgs.vllm` is hard-gated with
# `broken = cudaSupport` (pkgs/development/python-modules/vllm/default.nix).
# CUDA is the only backend these cards can use, so the package is unusable by
# construction. Upstream's image is the supported path.
#
# Hardware as measured on this machine, not assumed:
#   GPU0  0000:0b:00.0  RTX 3080 10GB  <- drives DP-2; niri + browsers already
#                                         hold ~3.4GB of it at idle
#   GPU1  0000:0c:00.0  RTX 3080 10GB  <- idle
# Both PCIe 4.0 x8 under a single host bridge, same NUMA node, no NVLink.
#
# Consequence: the usable inference budget is NOT the full 20GB. GPU0 has to go
# on serving the desktop, and a tensor-parallel split is symmetric — every rank
# gets the same allowance, so the busier card sets the ceiling for both. That
# lands around 6GB per rank, ~12GB total, which rules out a 30B-A3B AWQ
# checkpoint (~17GB) and comfortably fits a 14B with room for KV cache.
{
  config,
  lib,
  pkgs,
  ...
}: let
  port = 8000;

  # HF repo id. The tool-call parser has to match the model family, and getting
  # it wrong is not a soft failure: opencode receives prose where it expects a
  # structured call and every agent loop dies on its first tool invocation.
  #   Qwen3-*        -> "hermes"
  #   Qwen3-Coder-*  -> "qwen3_coder"
  model = "Qwen/Qwen3-14B-AWQ";
  toolCallParser = "hermes";

  # Fraction of EACH card's total VRAM vLLM may claim. 0.60 * 10240 ~= 6.1GB per
  # rank, ~12.2GB across the pair: a 14B at 4-bit is ~8.5GB, leaving ~3.5GB of
  # KV cache, while GPU0 keeps the ~3.4GB the compositor and browsers are using.
  # Past roughly 0.65 the desktop side runs out and Chrome starts OOMing tabs.
  # If the display ever moves off GPU0, this can go to 0.90 and the model can
  # grow to the 30B-A3B class.
  gpuFraction = "0.60";

  # Ampere (sm_86) has no FP8 tensor cores. Plain `fp8` resolves to fp8_e4m3,
  # which needs sm_89+; e5m2 is storage-only, dequantized on read, and is the
  # variant that works on these cards. Roughly doubles the context that fits.
  kvCacheDtype = "fp8_e5m2";

  # Agent loops spend 20-40K tokens on system prompt, tool schemas and file
  # reads before doing anything useful, so this is the floor worth running.
  maxModelLen = 32768;

  stateDir = "/var/lib/vllm";
in {
  # Wires hardware.nvidia-container-toolkit.enable (modules/rites/virtualisation.nix),
  # which generates the CDI spec behind --device=nvidia.com/gpu=all. podman
  # itself is already on for every workstation via stc/workstation.nix.
  services.imperium.virtualisation.podman.enableNvidia = true;

  # `/` is a btrfs subvolume rolled back to root-blank on every boot
  # (modules/rites/impermanence.nix) and /var/lib is not in the persisted set,
  # so without this the weights would be re-fetched after every single reboot.
  environment.persistence."/persist".directories = [stateDir];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${stateDir}/hf 0750 root root -"
  ];

  virtualisation.oci-containers.containers.vllm = {
    # Deliberately not `io.containers.autoupdate = registry`: vLLM changes and
    # removes server flags between releases, and an unattended pull that lands a
    # renamed flag leaves the unit crash-looping. Update by hand, or pin a tag.
    image = "vllm/vllm-openai:latest";

    # Off by default. The server reserves its whole VRAM allowance for as long
    # as it runs, which is the wrong standing trade on a workstation that also
    # drives a 4K display and plays games. Bring it up when you want it:
    #   systemctl start podman-vllm
    autoStart = false;

    # Published to loopback only, so no firewall change is needed. The container
    # binds 0.0.0.0 internally; the host side is what constrains reachability.
    ports = ["127.0.0.1:${toString port}:8000"];
    volumes = ["${stateDir}/hf:/root/.cache/huggingface"];

    extraOptions = [
      "--device=nvidia.com/gpu=all"
      # Tensor-parallel ranks hand tensors to each other through /dev/shm.
      # podman's default 64MB shm is far too small and the workers deadlock on
      # startup rather than failing with anything legible.
      "--ipc=host"
    ];

    environment = {
      HF_HOME = "/root/.cache/huggingface";
    };

    cmd = [
      "--model"
      model
      # Stable alias, so swapping `model` above does not mean editing
      # ~/.config/opencode/opencode.jsonc to match.
      "--served-model-name"
      "local-coder"
      "--tensor-parallel-size"
      "2"
      "--gpu-memory-utilization"
      gpuFraction
      "--kv-cache-dtype"
      kvCacheDtype
      "--max-model-len"
      (toString maxModelLen)
      "--enable-auto-tool-choice"
      "--tool-call-parser"
      toolCallParser
      "--host"
      "0.0.0.0"
      "--port"
      "8000"
    ];
  };
}
