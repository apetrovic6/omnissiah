{self, ...}: {
  flake.nixosModules.munitorum = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "sabnzbd";

    inherit (self.lib) mkRevProxyVHost mkDomain;
    inherit (lib) mkDefault mkIf mkOption mkEableOption types;

    imperiumBase = self.lib.mkImperiumService {
      inherit lib pkgs;
      name = serviceName;
    };

    cfg = config.services.imperium.${serviceName};
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {
      configFilePath = mkOption {
        type = types.str;
        default = "/var/lib/sabnzbd/sabnzbd.ini";
        description = "Path to the sabnzbd config file";
      };
    };

    config = mkIf cfg.enable {
      services.sabnzbd = {
        enable = true;
        package = cfg.package;
        user = cfg.user;
        group = cfg.group;
        openFirewall = cfg.openFirewall;
        configFile = cfg.configFilePath;
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost {port = cfg.port;};
        };
      };
    };
  };
}
