{self, ...}: {
  flake.nixosModules.lanzaboote = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.lanzaboote;
  in {
    imports = [
      self.inputs.lanzaboote.nixosModules.lanzaboote
    ];

    options.services.imperium.lanzaboote = {
      enable = mkEnableOption "Enable Lanzaboote and secure boot";
    };

    config = mkIf cfg.enable {
      boot.lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
      };

      boot.loader.systemd-boot.enable = lib.mkForce false;
    };
  };
}
