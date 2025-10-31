{ lib, pkgs, config, ... }:

let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.services.imperium.simpleHttp;
in
{
  options.services.imperium.bluetooth = {
    enable = mkEnableOption "Enable bluetooth and install needed programs";

    config = mkIf cfg.enable {
      hardware.bluetooth= {
        enable = true;
        powerOnBoot = true;
      };

      environment.systemPackages = with pkgs; [
        bluetui
        bluez
        bluez-utils
      ];
    };
  };
}
