{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "audiobookshelf";
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
    };

    config = mkIf cfg.enable {
      services.audiobookshelf = {
        enable = true;
        package = cfg.package;
        host = cfg.host;
        port = cfg.port;
        user = cfg.user;
        group = cfg.group;
        openFirewall = cfg.openFirewall;
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost cfg.port;
        };
      };
    };
  };
}
