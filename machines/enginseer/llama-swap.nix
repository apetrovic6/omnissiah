# llama-swap on the laptop: Qwen3.6-35B-A3B is its local model. Same entry
# name and ctxSize as on phalanx (../phalanx/llama-swap.nix), so the one
# llama-swap provider entry in magos (pi/omp) serves both machines.
#
# Measured 2026-11-26, 17.8K-token prompt, 400 generated: prefill 482 tok/s
# cold, decode 27.5-27.9 tok/s, warm turn re-reads 4 tokens; 6.8 of 8GB VRAM.
#
# 8GB of VRAM (RTX 4070 Laptop) and 32GB of RAM. The 16.5GB IQ4_XS file does
# not fit the card; it is an MoE with 3B active, so llama.cpp's auto-fit
# (no -ngl / -ot / --n-cpu-moe, see the phalanx file for why) keeps what fits
# on the GPU and spills experts to RAM. KV is cheap: only 10 of 40 layers are
# full attention, ~11KB/token at q8_0, ~1.4GB at 128K.
#
# The laptop runs no Strata: its Coder pack was never prepared, and on an 8GB
# card Strata's docs expect most of its experts to stream from the SSD.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Tests off: nixpkgs runs them for CUDA builds too, and they time out without
  # a GPU in the sandbox (details in ../phalanx/llama-swap.nix).
  llamaCpp = (pkgs.llama-cpp.override {cudaSupport = true;}).overrideAttrs {doCheck = false;};

  # In the user's home so models are fetched without sudo; bound read-only into
  # the service's namespace because ProtectHome blanks /home there.
  hostModelsDir = "/home/apetrovic/models";
  sandboxModelsDir = "/models";
in {
  services.llama-swap = {
    enable = true;
    listenAddress = "127.0.0.1";
    # Strata owns 8000.
    port = 8001;

    settings = {
      healthCheckTimeout = 600;

      models = {
        # Keep in sync with the llama-swap provider (contextWindow) in magos
        # modules/features/pi/default.nix and modules/features/omp/default.nix.
        "qwen36-35b-q4" = {
          ttl = 900;
          cmd = ''
            ${lib.getExe' llamaCpp "llama-server"} --port ''${PORT}
              --model ${sandboxModelsDir}/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf
              --ctx-size 131072
              --parallel 1
              --cache-type-k q8_0
              --cache-type-v q8_0
              --flash-attn on
              --jinja
              --no-webui
          '';
        };
      };
    };
  };

  systemd.services.llama-swap.path = [config.hardware.nvidia.package.bin];
  systemd.services.llama-swap.serviceConfig = {
    BindReadOnlyPaths = ["${hostModelsDir}:${sandboxModelsDir}"];
  };
}
