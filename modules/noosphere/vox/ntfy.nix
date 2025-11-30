{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "ntfy";
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

    };

    config = mkIf cfg.enable {
      services.ntfy-sh = {
        enable = true;
        package = cfg.package;
        host = cfg.host;
        port = cfg.port;
        user = cfg.user;
        group = cfg.group;
        openFirewall = cfg.openFirewall;
		settings = {
			upstream-base-url = "https://ntfy.sh";
		  
		};
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost cfg.port;
        };
      };
    };
  };
}
