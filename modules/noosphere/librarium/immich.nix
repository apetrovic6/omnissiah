{self, ...}: {
  flake.nixosModules.librarium = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "immich";

    inherit (self.lib) mkRevProxyVHost mkDomain;
    inherit (lib) mkDefault mkIf mkOption mkEnableOption types mkPackageOption;

    baseDomain =
      config.clan.core.vars.generators."caddy-env".files."domain".value;

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    cfg = config.services.imperium.${serviceName};
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {
      database = {
        name = mkOption {
          type = types.str;
          default = "immich";
          description = "Name for ${lib.toSentenceCase serviceName} database.";
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Host/interface for ${lib.toSentenceCase serviceName} to bind to.";
        };

        port = mkOption {
          type = types.port;
          default = 5432;
          description = "Port for ${lib.toSentenceCase serviceName} to listen on.";
        };

        user = mkOption {
          type = types.str;
          default = serviceName;
          description = "User account under which ${lib.toSentenceCase serviceName} should run.";
        };
      };

      mediaLocation = mkOption {
        type = types.str;
        default = "";
        description = "Photo location";
      };

      accelerationDevices = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "A list of device paths to hardware acceleration devices that immich should have access to. This is useful when transcoding media files. The special value [ ] will disallow all devices using PrivateDevices. null will give access to all devices.";
      };
    };

    config = mkIf cfg.enable {
      services.immich = {
        enable = true;
        package = cfg.package;

        host = cfg.host;
        port = cfg.port;
        openFirewall = cfg.openFirewall;

        user = cfg.user;
        group = cfg.group;

        machine-learning.enable = true;
        mediaLocation = cfg.mediaLocation;
        secretsFile = config.clan.core.vars.generators."${serviceName}-secrets".files."${serviceName}.env".path;

        accelerationDevices = cfg.accelerationDevices;
        
        settings.server = {
          externalDomain = "https://${cfg.subdomain}.${lib.trim baseDomain}";
        };

        redis = {
          enable = true;
        };
        
        database = with cfg.database; {
          enable = false;
          createDB = false;

          inherit user port host name;
        };

        
      };

      systemd.services.immich.after = ["immich-db-setup.service"];
      systemd.services.immich.wants = ["immich-db-setup.service"];

      services.postgresql.settings.shared_preload_libraries = "vchord.so";
      services.postgresql.settings.search_path = ''"$user", public, vectors'';

      systemd.services.immich-db-setup = {
        description = "Set up Immich database schema ownership";
        after = ["postgresql-password-init.service"];
        requires = ["postgresql-password-init.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
        };
        script = let
          psql = "${config.services.postgresql.package}/bin/psql";
        in ''
          set -euo pipefail
          ${psql} -d "${cfg.database.name}" -c "ALTER SCHEMA public OWNER TO ${cfg.database.user};"
        '';
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost {port = cfg.port;};
        };
      };

      clan.core.vars.generators."${serviceName}-secrets" = {
        share = false;
        files."${serviceName}.env" = {
          secret = true;
          mode = "0400";
          owner = cfg.user;
          group = cfg.group;
        };
        dependencies = ["postgresql-${serviceName}"];
        script = ''
          PASSWORD=$(cat "$in/postgresql-${serviceName}/password")
          echo "DB_PASSWORD=$PASSWORD" > "$out/${serviceName}.env"
        '';
      };

    };
  };
}
