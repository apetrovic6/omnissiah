{self, ...}: {
  imports = [self.nixosModules.strata];

  # RTX 4070 Laptop (Ada), not phalanx's Ampere build target.
  nixpkgs.config.cudaCapabilities = ["8.9"];

  services.imperium.strata = {
    enable = true;
    user = "apetrovic";
    family = "coder";
    gpu = 0;
    maxContext = 32768;
    # Release RAM/VRAM sooner on the laptop; the next request cold-loads.
    idleUnload = 900;
  };
}
