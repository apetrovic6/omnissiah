{self, ...}: {
  flake.nixosModules.bluetooth = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.bluetooth;
  in {
    options.services.imperium.bluetooth = {
      enable = mkEnableOption "Enable bluetooth and install needed programs";
    };

    config = mkIf cfg.enable {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings = {
          General.ControllerMode = "le";
        };
      };

      environment.systemPackages = with pkgs; [
        bluetui
      ];
    };
  };
}
