{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "nzbhydra2";
    inherit (self.lib) mkRevProxyVHost mkDomain;

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf;
    cfg = config.services.imperium.${serviceName};
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {};

    config = mkIf cfg.enable {
      services.nzbhydra2 = {
        enable = true;
        package = cfg.package;
        openFirewall = cfg.openFirewall;
        dataDir = "/var/lib/nzbhydra2";
      };

      services.caddy.virtualHosts."${mkDomain cfg.subdomain}" = {
        extraConfig = mkRevProxyVHost cfg.port;
      };
    };
  };
}
