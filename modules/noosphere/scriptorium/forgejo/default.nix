{self, ...}: {
  flake.nixosModules.scriptorium = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "forgejo";

    imperiumBase = import ../../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption types mkEnableOption optionalAttrs;
    inherit (self.lib) mkRevProxyVHost mkDomain;

    cfg = config.services.imperium.${serviceName};
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {
      sshPort = mkOption {
        type = types.port;
        default = 22;
        description = "Port for SSH";
      };

      domain = mkOption {
        type = types.str;
        default = "";
        description = "Domain of the server";
      };

      rootUrl = mkOption {
        type = types.str;
        default = "http://${cfg.subdomain}.${cfg.domain}";
        description = "Full public URL of Forgejo server";
      };

      disableSsh = mkOption {
        type = types.bool;
        default = false;
        description = "Disable external SSH feature";
      };

      startSshServer = mkOption {
        type = types.bool;
        default = true;
        description = "Start SSH server";
      };

      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/forgejo";
        description = "Directory for the Forgejo state";
      };

      lfs = {
        enable = mkEnableOption "LFS support";

        contentDir = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Where to store LFS files; null uses Forgejo default (\${stateDir}/data/lfs)";
        };
      };

      dump = {
        enable = mkEnableOption "periodic Forgejo dumps";

        interval = mkOption {
          type = types.str;
          default = "04:31";
          description = "Systemd timer interval for dumps (systemd.time format)";
        };

        backupDir = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Directory for dump archives; null uses Forgejo default (\${stateDir}/dump)";
        };

        type = mkOption {
          type = types.enum ["zip" "tar" "tar.sz" "tar.gz" "tar.xz" "tar.bz2" "tar.br" "tar.lz4" "tar.zst"];
          default = "zip";
          description = "Archive format for dumps";
        };

        file = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Custom filename for dumps; null uses Forgejo defaults";
        };

        age = mkOption {
          type = types.str;
          default = "4w";
          description = "Retention period for dumps in tmpfiles.d format";
        };
      };

      database = {
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Database host";
        };

        port = mkOption {
          type = types.port;
          default = 5432;
          description = "Database port";
        };

        name = mkOption {
          type = types.str;
          default = "forgejo";
          description = "Database name";
        };

        user = mkOption {
          type = types.str;
          default = "forgejo";
          description = "Database user";
        };

        socket = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Unix socket path for database connection; overrides host/port when set";
        };

        createDatabase = mkOption {
          type = types.bool;
          default = false;
          description = "Automatically provision local database";
        };
      };

      secrets = mkOption {
        type = types.attrsOf (types.attrsOf types.path);
        default = {};
        description = ''
          Extra secrets to pass to Forgejo's INI configuration. Attribute names
          are INI section names and values are attrsets mapping INI keys to secret
          file paths. Values are loaded as systemd credentials at runtime and take
          precedence over the same keys in settings.
        '';
        example = lib.literalExpression ''
          {
            service.HCAPTCHA_SECRET = "/run/secrets/forgejo-hcaptcha";
            mailer.PASSWD = "/run/secrets/smtp-password";
          }
        '';
      };
    };

    config = mkIf cfg.enable {
      services.forgejo = {
        enable = true;

        user = cfg.user;
        group = cfg.user;

        stateDir = cfg.stateDir;

        lfs =
          {enable = cfg.lfs.enable;}
          // optionalAttrs (cfg.lfs.contentDir != null) {
            contentDir = cfg.lfs.contentDir;
          };

        dump =
          {inherit (cfg.dump) enable interval type age;}
          // optionalAttrs (cfg.dump.backupDir != null) {backupDir = cfg.dump.backupDir;}
          // optionalAttrs (cfg.dump.file != null) {file = cfg.dump.file;};

        database =
          {
            type = "postgres";
            inherit (cfg.database) host port name user createDatabase;
            passwordFile = config.clan.core.vars.generators."forgejo-db".files."db-password".path;
          }
          // optionalAttrs (cfg.database.socket != null) {socket = cfg.database.socket;};

        secrets = cfg.secrets;

        settings.server = {
          HTTP_PORT = cfg.port;
          SSH_PORT = cfg.sshPort;
          ROOT_URL = cfg.rootUrl;
          DISABLE_SSH = cfg.disableSsh;
          START_SSH_SERVER = cfg.startSshServer;
          HTTP_ADDR = cfg.host;
          DOMAIN = cfg.domain;
        };

        settings.session.COOKIE_SECURE = true;
      };

      services.caddy.virtualHosts."${mkDomain cfg.subdomain}" = {
        extraConfig = mkRevProxyVHost {port = cfg.port;};
      };

      clan.core.vars.generators."forgejo-db" = {
        share = false;

        files."db-password" = {
          secret = true;
          owner = cfg.user;
          group = cfg.user;
          mode = "0400";
        };

        prompts.password = {
          description = "Database password for Forgejo (${cfg.database.user}@${cfg.database.host}/${cfg.database.name})";
          type = "hidden";
          persist = true;
        };

        script = ''
          cp "$prompts/password" "$out/db-password"
        '';
      };
    };
  };
}
