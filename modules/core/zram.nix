{self, ...}: {
  flake.nixosModules.zram = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.zram;
  in {
    options.services.imperium.zram = {
      enable = mkEnableOption "Enable zram swap";
    };

    config = lib.mkIf cfg.enable {
      zramSwap = {
        enable = true;
        # one of "lzo", "lz4", "zstd"
        algorithm = "zstd";
        priority = 5;
        memoryPercent = 50;
      };
    };
  };
}
