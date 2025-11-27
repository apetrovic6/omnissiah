{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "navidrome";
    inherit (self.lib) mkRevProxyVHost mkDomain;
    inherit (lib)  mkDefault;
    
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
      services.navidrome = {
        enable = true;
        package = cfg.package;
        settings = {
          Address= mkDefault cfg.host;
          Port = mkDefault cfg.port;
          MusicFolder = mkDefault "${config.services.imperium.smb.hosts.manjaca.shares.data.mountPoint}/media/music";
          # DataFolder = "${config.services.imperium.smb.hosts.manjaca.shares.selfhosted.mountPoint}/navidrome";
          DataFolder = mkDefault "/var/lib/navidrome";
        };
        user = mkDefault cfg.user;
        group = mkDefault cfg.group;
        openFirewall = mkDefault cfg.openFirewall;
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost cfg.port;
        };
      };
    };
  };
}
