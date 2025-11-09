{self, ...}: {
  flake.nixosModules.bluetooth = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.magos.bluetooth;
  in {
    options.services.magos.bluetooth = {
      enable = mkEnableOption "Enable bluetooth and install needed programs";
    };

    config = mkIf cfg.enable {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      environment.systemPackages = with pkgs; [
        bluetui
      ];
    };
  };
}
