# Strata -- the inference engine for Qwen3.8-Flash-Next, replacing both
# ./llama-cpp.nix and ./llama-swap.nix (both left on disk, no longer imported).
#
# Why it replaced llama.cpp, measured on this machine 2026-10-15 with a
# 31,086-token prompt built from this repo's own .nix files:
#
#                      llama.cpp qwen38-flash-q3   Strata IQ3_XXS
#   decode                    ~21 tok/s            39.5 - 42.6 tok/s
#   prefill (cold)     "minutes" at 128K           1340 tok/s (~98s at 128K)
#   prefill (warm)     re-prefill after compaction ~free: 31081/31086 cached
#   MTP speculation    crashes on stock llama.cpp  working, 72-79% accepted
#
# Prefill was the binding constraint on the old setup, and it is the number
# that moved most. MTP is the other win: ./llama-swap.nix carries a long
# comment explaining why qwen4exp MTP aborts on stock llama.cpp; Strata ships
# its own MTP path and enables it by default (--spec 4 in the engine config).
#
# WHAT NIX OWNS NOW, AND WHAT IT DOES NOT. The engine and the server are built
# from the `strata` flake input (./strata-package.nix), and the engine config
# that ./setup.sh used to write is generated below. Updating Strata is: bump the
# tag on the `strata` input in flake.nix, `nix flake update strata`, deploy.
# There is no checkout, no venv and no ./setup.sh in the loop any more.
#
# The model DATA in ~/models/strata-data is still imperative: the GGUFs, the
# pack setup.py extracted from them (tokenizer included), and the MTP draft
# head. A Strata release that changes one of those formats needs a one-off
# ./setup.sh run from a checkout of that release; the engine refuses a pack it
# cannot read, so that shows up as a start failure, not as silent garbage.
#
# WHY A USER SERVICE, not a system one: the model data lives in the home
# directory and is owned by apetrovic. A system unit would need ProtectHome off
# plus a fixed uid to read 80 GB of someone else's files; a user service just
# runs as the owner.
{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  strata = pkgs.callPackage ./strata-package.nix {
    src = self.inputs.strata;
    llamaCpp = self.inputs.strata-llama-cpp;
  };

  # Written by ./setup.sh once, persisted by the "models" entry in
  # modules/rites/impermanence.nix.
  data = "/home/apetrovic/models/strata-data";

  # Writable state: the engine log, and whatever the server keeps next to its
  # --config (`.shared-settings.json`, `.tool-media/`). Persisted via
  # ".local/state/strata" in modules/rites/impermanence.nix.
  stateDir = "/home/apetrovic/.local/state/strata";

  # 8000 on purpose: the port ./llama-swap.nix used, so the llama-swap provider
  # in magos modules/features/pi/default.nix keeps working with no change to
  # its baseUrl.
  port = 8000;

  # ONLY ONE GPU, AND THAT IS MEASURED, NOT AN OVERSIGHT. The engine config
  # carries "gpu": 1 -- physical card 1, the idle one; card 0 drives DP-2 and is
  # left to niri. The obvious objection is that ~4.8 GB of VRAM on card 0 sits
  # unused, so it was tried properly. Same 31k prompt, cold cache, 2026-10-15:
  #
  #                               prefill      decode    primary cache hit
  #   single GPU (this config)    1340 tok/s   39.5      60.1%
  #   --peer-device, PEER_HOT .45 1582 (+18%)  30.5      53.2%
  #   --peer-device, PEER_HOT .12 1583 (+18%)  28.7      53.3%
  #
  # The second card buys 18% prefill and costs ~25% DECODE. Decode is what an
  # interactive session spends its time on, and prefill is already cheap here
  # because the prefix cache turns a repeat 31k prompt into 5 tokens.
  #
  # The cause is the interconnect, not a tuning mistake. These 3080s have no
  # NVLink and sit on PCIe 4.0 x8 under one bridge, so the engine reports
  # "no P2P: through mapped host memory in FP16" and every peer-resident expert
  # costs a host round trip per token -- worse than the CPU path it replaces.
  # --peer-device also turns off adaptive overlap ("adaptive overlap: off: not
  # with --peer-device").
  #
  # STRATA_PEER_HOT was tested as the fix and is NOT one: dropping it from 0.45
  # to 0.12 moved 1044 hot pairs to the peer instead of 3915, and changed the hit
  # rate by 0.1 points and decode not at all. The cost is the mechanism itself.
  #
  # Also settled: --expert-cache-device1 cannot be used here. Giving the server a
  # GPU LIST makes it infer a layer split and append --layer-split auto, and the
  # engine then refuses ("--expert-cache-remote with a layer split needs a GPU
  # that runs no stage"). Only --peer-device suppresses that split, and the two
  # flags are mutually exclusive.
  #
  # Re-open only with new hardware (a P2P-capable pair) or a prefill-bound
  # workload that does not reuse its prompts.

  # HUGE PAGES: TRIED, REVERTED. The engine logs a 39 GiB expert arena running
  # on 4 KiB pages ("MAP_HUGETLB unavailable ... vm.nr_hugepages=0"), which
  # looks like free performance. It is not, measured 2026-10-15:
  #
  #                          prefill   decode   load+bench wall
  #   baseline               1340      39.5     ~80 s
  #   STRATA_ARENA_THP=1     1334      38.2     351 s
  #
  # The flag works (the log flips to "transparent huge pages requested
  # (MADV_HUGEPAGE)" and AnonHugePages went 15.8 -> 21.1 GiB) but throughput is
  # unchanged within noise, and the engine's own warning is accurate --
  # "compaction would stall the load" turned a ~50 s cold load into ~5 minutes.
  # With idle-unload that penalty is paid every time the model comes back.
  #
  # vm.nr_hugepages is the WRONG fix for the same idea: it would reserve ~40 GiB
  # permanently, which cannot be reclaimed while the model is unloaded and so
  # defeats --idle-unload entirely.

  # What ./setup.sh wrote to strata-iq3_xxs.json for this machine, with the
  # paths into the old checkout swapped for the store and the state dir.
  # `model_name` must match the strata models in magos
  # modules/features/pi/default.nix exactly.
  engineConfig = pkgs.writeText "strata-iq3_xxs.json" (builtins.toJSON {
    exe = "${strata.engine}/libexec/strata/strata";
    args = [
      "--pack"
      "${data}/packs/iq3_xxs"
      "--native"
      "${data}/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf"
      "--ple-gguf"
      "${data}/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.gguf"
      "--expert-profile"
      "${strata.src}/data/expert-profile.bin"
      "--expert-cache"
      "auto"
      "--prefill"
      "auto"
      "--spec"
      "4"
      "--spec-min-p"
      "0.5"
      "--mtp"
      "${data}/mtp/rt"
      # The model's trained length; setup.py's default would be 131072.
      "--max-context"
      "262144"
      "--kv"
      "int8"
      "--kv-resident"
      "32768"
    ];
    cwd = stateDir;
    tokenizer = "${data}/packs/iq3_xxs/tokenizer";
    model_name = "qwen3.8-flash-next-iq3_xxs";
    log = "${stateDir}/strata-iq3_xxs.log";
    # The CUDA libraries are in the engine's RUNPATH now, so the server has
    # nothing to prepend to LD_LIBRARY_PATH -- and, unlike the old
    # cuda-merged path here, nothing the garbage collector can pull out from
    # under a stopped service.
    lib_dirs = [];
    inherit port;
    gpu = 1;
    gpus_asked = true;
  });
in {
  systemd.user.services.strata = {
    description = "Strata inference engine (Qwen3.8-Flash-Next IQ3_XXS)";
    wantedBy = ["default.target"];

    # nvidia-smi: the server shells out to it for the VRAM figures in
    # /v1/status and for the --min-free-vram-mib check below. It lives in the
    # driver package's `bin` output, not `out` -- same trap ./llama-swap.nix
    # documents.
    path = [config.hardware.nvidia.package.bin];

    serviceConfig = {
      Type = "simple";
      # A user unit's StateDirectory is ~/.local/state/<name>: creates stateDir.
      StateDirectory = "strata";
      WorkingDirectory = stateDir;

      # The server writes next to its --config (see stateDir), so it gets a
      # path in the state dir; the symlink keeps the content in the store.
      ExecStartPre = "${pkgs.coreutils}/bin/ln -sfn ${engineConfig} ${stateDir}/strata-iq3_xxs.json";

      # --lazy + --idle-unload together reproduce llama-swap's per-model `ttl`:
      # the Python proxy starts at login and costs nothing, the 79GB engine
      # loads on the first request and hands the RAM back when idle.
      #
      # 3600, not a shorter value: a cold load is ~50s here (measured, NVMe;
      # upstream quotes 80-105s on SATA) and it also discards the prefix cache,
      # which is worth more than the load -- a warm 31k prompt re-prefilled 5
      # tokens instead of 31086.
      #
      # --min-free-vram-mib 2048 is a guard ./llama-swap.nix had no equivalent
      # for: with a game already holding the card, Strata answers 503 instead
      # of loading into whatever is left and aborting mid-reply. 2048 is a
      # starting guess -- the expert cache alone took 3.09 GiB at last load.
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe strata.server)
        "--engine strata"
        "--config ${stateDir}/strata-iq3_xxs.json"
        "--port ${toString port}"
        "--lazy"
        "--idle-unload 3600"
        "--min-free-vram-mib 2048"
      ];

      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
