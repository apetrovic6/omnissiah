{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "caddy";

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption mkEnableOption types mkPackageOption toSentenceCase;
    cfg = config.services.imperium.${serviceName};
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/caddy";
        description = ''
          The data directory for ${toSentenceCase serviceName}.

          ::: {.note}
          If left as the default value this directory will automatically be created
          before the ${toSentenceCase serviceName}server starts, otherwise you are responsible for ensuring
          the directory exists with appropriate ownership and permissions.

          Caddy v2 replaced `CADDYPATH` with XDG directories.
          See <https://caddyserver.com/docs/conventions#file-locations>.
          :::
        '';
      };

      logDir = mkOption {
        type = types.path;
        default = "/var/log/caddy";
        description = ''
          Directory for storing ${toSentenceCase serviceName} access logs.

          ::: {.note}
          If left as the default value this directory will automatically be created
          before the ${toSentenceCase serviceName} server starts, otherwise the sysadmin is responsible for
          ensuring the directory exists with appropriate ownership and permissions.
          :::
        '';
      };
    };

    config = mkIf cfg.enable {
      services.caddy = {
        enable = true;
        package = cfg.package;
        user = cfg.user;
        group = cfg.group;
      };
    };
  };
}
