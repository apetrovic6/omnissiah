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
# v0.2.11 -> v0.2.17 (engine 0.1.57 -> 0.1.63), measured 2026-11-21, single
# GPU, same method (35,316-token prompt from this repo's .nix files, temp 0,
# 400 generated tokens):
#
#                      v0.2.11 (above)   v0.2.17
#   decode             39.5 - 42.6       55.0 cold / 58.6 warm tok/s
#   prefill (cold)     1340 tok/s        1129 tok/s (31 s for 35K)
#   prefill (warm)     ~free             5 of 35,316 tokens re-processed
#   MTP accepted       72-79%            65-70%
#
# Decode is the gain (~+35%), despite 0.2.17 turning the route tail skip off
# by default (STRATA_ROUTE_TAIL_SKIP=7 re-enables it). Prefill is not directly
# comparable -- longer prompt, different files -- so treat it as "unchanged
# within the noise", not a regression. The two-GPU notes below were re-run on
# 0.2.17 with a layer split; single-GPU still wins.
#
{self, ...}: {
  imports = [self.nixosModules.strata];

  # Served through llama-swap (./llama-swap.nix) since 2026-11-27: one entry per
  # Strata model, so llama-swap decides what holds GPU1 and asking for one
  # model unloads the other. The paths below are the service's view of
  # ~/models (its BindReadOnlyPaths).
  services.imperium.strata = {
    enable = true;
    dataDir = "/models/strata-data";
    gpu = 1;

    qwen.family = "qwen";
    qwen.quant = "IQ3_XXS";

    # ROUTE TAIL SKIP: ON, measured 2026-11-21 on v0.2.17. When an expert the
    # router ranked 7th or lower for every token in the window is not cached
    # on the GPU, the engine skips it instead of fetching it from RAM. Upstream
    # turned it OFF by default in 0.2.17 because it changes answer text
    # slightly -- an approximation, not a free speedup. Same 35K benchmark,
    # three runs each, decode tok/s cold / warm:
    #
    #   off (default)   55.0/58.6  51.5/61.4  52.0/52.2
    #   7               68.5/71.0  65.8/69.3  (28.3/22.6 outlier, not repeated)
    #
    # About +20-25% decode, more than upstream's +8% on 2x A4000 -- plausibly
    # because a 10GB card misses more experts, so there is more to skip.
    # Prefill unchanged (~1060-1130 tok/s). Set "0" to compare quality.
    qwen.engineEnv.STRATA_ROUTE_TAIL_SKIP = "7";
    qwen.maxContext = 262144;
    qwen.ttl = 3600;

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
    # LAYER SPLIT, re-tested 2026-11-21 on v0.2.17 ("gpu": [0, 1],
    # "layer_split": "auto"; not the --peer-device path above). Each card runs
    # a contiguous range of layers with its own expert cache, handing the token
    # over through pinned RAM, so the missing P2P does not matter here. Same 35K
    # benchmark, tail skip 7 on both, two reps:
    #
    #                    prefill (cold)   decode cold / warm
    #   single GPU 1     1120-1130        65.8-68.5 / 69.3-71.0
    #   layer split 0+1    744-807        64.0-84.1 / 73.8-79.8
    #
    # Decode maybe +10% (the two reps alone span 64-84), prefill -30% even with
    # 0.2.16's two-card CPU prefill share on by default, and card 0 -- the
    # display card -- went to 9.2 of 10 GB, leaving the desktop and browsers
    # almost nothing. Not worth it; stays single-GPU.
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

    # INKLING 2 MINI on Strata's own engine (strata-inkling, 0.2.19+), SQ-15
    # pack, replacing the llama.cpp route in ./llama-swap.nix. Measured
    # 2026-11-27, GPU1, 128K ctx, the same 20.6K-token prompt, tok/s:
    #
    #                                         prefill (cold)   decode
    #   llama.cpp, layers 8-17 on GPU, ub256      139.7        26.5-27.3
    #   strata-inkling SQ-15, drafting off        657-730      16.1-16.7
    #   strata-inkling SQ-15, DSpark on           725          11.9-12.0
    #
    # Strata reads 5x faster and writes 1.6x slower. Agent turns are mostly
    # reading, so it wins there: yesterday's 45.5K-read / 3.4K-written pi
    # session is ~4.5 min here against ~7.5 on llama.cpp. The engine keeps
    # 1,555 of 3,072 experts in VRAM and computes the rest on the CPU (its
    # launch probe: CPU 20 ms/token, copying to the card 43 ms).
    #
    # Left off, measured: DSpark (35% of drafts accepted, decode 12 tok/s --
    # Strata's own default is off), 32K context (decode unchanged: the expert
    # pool, not the KV, fills the card) and STRATA_INK_DEC_PCIE_SHARE (no
    # effect; STRATA_INK_EXACT picks the lane).
    inkling = {
      enable = true;
      pack = "SQ-15";
      maxContext = 131072;
      drafting = "off";
    };
  };
}
