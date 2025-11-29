{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "tautulli";
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
       configFile = mkOption {
        type = types.str;
        default = "/var/lib/plexpy/config.ini";
        description = "The location of Tautulli's config file";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/plexpy";
        Description = "The directory where Tautulli stores its data files";
      };
    };

    config = mkIf cfg.enable {
      services.tautulli = {
        enable = true;
        package = cfg.package;
        user = cfg.user;
        group = cfg.group;
        openFirewall = cfg.openFirewall;
        configFile = cfg.configFile;
        dataDir = cfg.dataDir;
      };


      environment.persistence."/persist".directories = ["/var/lib/plex"];
      
      
      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost cfg.port;
        };
      };
    };
  };
}
