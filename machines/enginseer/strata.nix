# Inkling 2 Mini on Strata's own engine (strata-inkling), served through
# llama-swap (./llama-swap.nix) beside the Qwen3.6 llama.cpp entry. Qwen on
# Strata stays off here: its Coder pack was never prepared.
#
# SQ-10 because Strata sizes it for "4-8 GiB hybrid cards", and this laptop's
# RTX 4070 is 8 GB. SQ-15 is the 12-16 GiB pack.
#
# SPEED ON THIS LAPTOP IS NOT MEASURED YET. For scale only, phalanx runs SQ-15
# on a 10 GB 3080: prefill 657-730 tok/s, decode 16-17 tok/s (see
# ../phalanx/strata.nix). Do not read those as predictions for this machine.
{self, ...}: {
  imports = [self.nixosModules.strata];

  # dataDir is the service's view of ~/models (BindReadOnlyPaths in
  # ./llama-swap.nix).
  services.imperium.strata = {
    enable = true;
    dataDir = "/models/strata-data";
    gpu = 0;
    qwen.enable = false;
    inkling = {
      enable = true;
      pack = "SQ-10";
      maxContext = 262144;
      drafting = "off";
    };
  };
}
