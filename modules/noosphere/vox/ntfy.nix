{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "ntfy-sh";
    inherit (self.lib) mkRevProxyVHost mkDomain;

    baseDomain =
      config.clan.core.vars.generators."caddy-env".files."domain".value;

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption mkEnableOption types mkPackageOption;
    cfg = config.services.imperium.${serviceName};

    ntfyStateDir = "/var/lib/ntfy-sh";
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {};

    config = mkIf cfg.enable {
      services.ntfy-sh = {
        enable = true;
        package = cfg.package;
        user = cfg.user;
        group = cfg.group;

        settings = {
          base-url = "https://${cfg.subdomain}.${lib.trim baseDomain}";
          listen-http = ":${toString cfg.port}";
          upstream-base-url = "https://ntfy.sh";

          # point ntfy to the writable state dir
          cache-file = "${ntfyStateDir}/cache.db";
          attachment-cache-dir = "${ntfyStateDir}/attachments";
          auth-file = "${ntfyStateDir}/auth.db";
        };
      };

      services.caddy.virtualHosts."${mkDomain cfg.subdomain}" = {
        extraConfig = mkRevProxyVHost cfg.port;
      };
    };
  };
}
