{self, ...}: {
  flake.nixosModules.impermanence = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.impermanence;
  in {
    options.services.magos.bluetooth = {
      enable = mkEnableOption "Enable Impermanence";
    };

    config = mkIf cfg.enable {
      imports = [
        impermanence.nixosModules.impermanence
      ];

      

    };
  };
}
