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
# WHY A USER SERVICE, not a system one. Strata needs a WRITABLE checkout: the
# venv, strata-iq3_xxs.json and strata-iq3_xxs.log all live in it, and
# setup.sh rewrites them on every run. The old llama-swap unit ran
# DynamicUser=true + ProtectHome=true, which blanks /home in the namespace and
# gives the service a transient uid that cannot write a checkout owned by
# apetrovic. A user service sidesteps all of it -- it runs as the user and
# sees the home directory natively, no BindPaths, no StateDirectory.
#
# The cost is that the checkout is imperative: it is a git clone driven by
# ./setup.sh, not a derivation. Strata ships no package output, only a devShell
# (see its flake.nix), so there is nothing to build here. Treated the same way
# the models in ~/models are treated: state, persisted by impermanence.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # The checkout ./setup.sh produced. Persisted via the "programming" entry in
  # users.apetrovic.directories (modules/rites/impermanence.nix).
  checkout = "/home/apetrovic/programming/Strata";

  # Written by setup.py; holds the engine path, the GGUF paths and the tuned
  # engine flags (--expert-cache auto, --spec 4, --kv int8, --kv-resident
  # 32768). Do not hand-edit: a later ./setup.sh overwrites it.
  configFile = "${checkout}/strata-iq3_xxs.json";

  # 8000 on purpose: the port ./llama-swap.nix used, so the llama-swap provider
  # in magos modules/features/pi/default.nix keeps working with no change to
  # its baseUrl.
  port = 8000;

  # ONLY ONE GPU, AND THAT IS MEASURED, NOT AN OVERSIGHT. strata-iq3_xxs.json
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

  # strata-iq3_xxs.json pins an absolute /nix/store path in its `lib_dirs`
  # (the merged CUDA 13.0 toolkit the engine dlopens). NOTHING in the system
  # closure references it -- `nix-store --query --roots` on it returned only
  # /proc/<pid>/environ of the running processes. So once Strata stops, the
  # next `nix-collect-garbage` deletes it and the engine dies on a missing
  # library, naming a store path and giving no hint that a GC caused it.
  #
  # This re-pins it before every start, reading whatever path the config
  # currently names, so it survives setup.sh regenerating the config with a
  # different CUDA build.
  pinCuda = pkgs.writeShellScript "strata-pin-cuda" ''
    set -eu
    lib=$(${pkgs.jq}/bin/jq -r '.lib_dirs[0] // empty' ${configFile})
    if [ -n "$lib" ] && [ -e "$lib" ]; then
      ${pkgs.nix}/bin/nix-store --add-root ${checkout}/.cuda-gcroot \
        --indirect -r "$lib" >/dev/null
    fi
  '';
in {
  systemd.user.services.strata = {
    description = "Strata inference engine (Qwen3.8-Flash-Next IQ3_XXS)";
    wantedBy = ["default.target"];

    # nvidia-smi: the server shells out to it for the VRAM figures in
    # /v1/status and for the --min-free-vram-mib check below. It lives in the
    # driver package's `bin` output, not `out` -- same trap ./llama-swap.nix
    # documents.
    path = [config.hardware.nvidia.package.bin];

    # The engine dlopens libcuda.so, which on NixOS exists ONLY in
    # /run/opengl-driver/lib -- that is the DRIVER; the CUDA toolkit ships a
    # stub of the same name. Strata's server does NOT assemble this path
    # itself: it only PREPENDS the config's `lib_dirs` to whatever
    # LD_LIBRARY_PATH it inherited. Under `nix develop` that inheritance came
    # from the flake's shellHook, which is why running it by hand worked and
    # the first service start did not:
    #
    #   strata generate: native embedding: cannot pin 260 MiB: CUDA driver is
    #     a stub library, nor place it in VRAM; the next request restarts it
    #   the engine process ended: exit code 1
    #
    # libstdc++ and zlib are the other two the shellHook supplied.
    environment.LD_LIBRARY_PATH =
      "/run/opengl-driver/lib:"
      + lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib pkgs.zlib];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = checkout;
      ExecStartPre = "${pinCuda}";

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
        "${checkout}/.venv/bin/python"
        "${checkout}/serve/server.py"
        "--engine strata"
        "--config ${configFile}"
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
