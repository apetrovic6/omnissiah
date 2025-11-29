{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "plex";
    inherit (self.lib) mkRevProxyVHost mkDomain;

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption mkEnableOption types mkPackageOption;
    cfg = config.services.imperium.${serviceName};
  in {
    imports = [
      imperiumBase
    ];

    options.services.imperium.${serviceName} = {
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open ports in the firewall for the Audiobookshelf web interface";
      };

      accelerationDevices = mkOption {
        type = types.bool;
        default = [ "*" ];
        description = "Devices that Plex can use for transcoding etc.";
      };
    };

    config = mkIf cfg.enable {
      services.plex = {
        enable = true;
        package = cfg.package;
        host = cfg.host;
        port = cfg.port;
        user = cfg.user;
        group = cfg.group;
        openFirewall = cfg.openFirewall;
        accelerationDevices = cfg.accelerationDevices;
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost cfg.port;
        };
      };
    };
  };
}
