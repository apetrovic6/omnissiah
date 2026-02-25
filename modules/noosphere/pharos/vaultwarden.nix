{self, ...}: {
  flake.nixosModules.pharos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "vaultwarden";
    inherit (self.lib) mkRevProxyVHost mkDomain;
    inherit (lib) mkEnableOption mkPackageOption toSentenceCase mkOption types mkIf;

    baseDomain =
      config.clan.core.vars.generators."caddy-env".files."domain".value;

    cfg = config.services.imperium.${serviceName};
  in {
    options.services.imperium.${serviceName} = {
      enable = mkEnableOption "Enable ${toSentenceCase serviceName}";
      package = mkPackageOption pkgs serviceName {};

      port = mkOption {
        type = types.int;
        default = 8222;
        description = "Port on which will Vaultwarden be exposed";
      };

      dbBackend = mkOption {
        type = types.enum ["postgresql" "mysql"];
        default = "postgresql";
        description = "DB backend Vaultwarden will use";
      };

      backupDir = mkOption {
        type = types.str;
        default = "";
        description = "/var/backup/vaultwarden";
      };

      subdomain = mkOption {
        type = types.str;
        default = serviceName;
        description = "Subdomain under which ${toSentenceCase serviceName} will be exposed.";
      };

      environmentFile = mkOption {
        type = with lib.types; coercedTo path lib.singleton (listOf path);
        default = [];
        example = "/var/lib/vaultwarden.env";
        description = ''
          '';
      };

      config = mkOption {
        type = with types; attrsOf (nullOr (oneOf [bool int str]));
        default = {
          ROCKET_ADDRESS = "::1";
          ROCKET_PORT = 8222;
        };
        example = lib.literalExpression ''
          {
           DOMAIN = "https://bitwarden.example.com";
           SIGNUPS_ALLOWED = false;

           # Vaultwarden recommends running behind a reverse proxy, the configureNginx option can be used for that.
           ROCKET_ADDRESS = "127.0.0.1";
           ROCKET_PORT = 8222;

           ROCKET_LOG = "critical";

           # This example assumes a mailserver running on localhost,
           # thus without transport encryption.
           # If you use an external mail server, follow:
           #   https://github.com/dani-garcia/vaultwarden/wiki/SMTP-configuration
           SMTP_HOST = "127.0.0.1";
           SMTP_PORT = 25;
           SMTP_SSL = false;

           SMTP_FROM = "admin@bitwarden.example.com";
           SMTP_FROM_NAME = "example.com Bitwarden server";
          }
        '';
      };
    };

    config = mkIf cfg.enable {
      services.vaultwarden = {
        enable = true;
        configurePostgres = false;
        configureNginx = false;
        dbBackend = cfg.dbBackend;
        backupDir = lib.mkIf (cfg.dbBackend == "sqlite") cfg.backupDir;
        config =
          cfg.config
          // {
            ROCKET_PORT = cfg.port;
            DOMAIN = "https://${cfg.subdomain}.${baseDomain}";
          };
        environmentFile = cfg.environmentFile ++ [
          config.clan.core.vars.generators.vaultwarden-admin-token.files.vaultwarden-env.path
          config.clan.core.vars.generators.vaultwarden-db.files.vaultwarden-db-env.path
        ];
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost {port = cfg.port;};
        };
      };


      clan.core.vars.generators.vaultwarden-db = {
        share = false;

        files.vaultwarden-db-env = {
          secret = true;
          mode = "0400";
        };

        prompts.db-host = {
          description = "PostgreSQL host for Vaultwarden";
          type = "line";
        };

        prompts.db-port = {
          description = "PostgreSQL port for Vaultwarden";
          type = "line";
        };

        prompts.db-name = {
          description = "PostgreSQL database name for Vaultwarden";
          type = "line";
        };

        prompts.db-username = {
          description = "PostgreSQL username for Vaultwarden";
          type = "line";
        };

        prompts.db-password = {
          description = "PostgreSQL password for Vaultwarden";
          type = "hidden";
          persist = false;
        };

        script = ''
          DB_HOST=$(cat "$prompts/db-host")
          DB_PORT=$(cat "$prompts/db-port")
          DB_NAME=$(cat "$prompts/db-name")
          DB_USER=$(cat "$prompts/db-username")
          DB_PASS=$(cat "$prompts/db-password")
          echo "DATABASE_URL=postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME" > "$out/vaultwarden-db-env"
        '';
      };

      clan.core.vars.generators.vaultwarden-admin-token= {
        share = false;

        files.vaultwarden-env= {
          secret = true;
          mode = "0400";
        };

        prompts.admin-token = {
          description = "Admin token for Vaultwarden instance";
          type = "hidden";
          persist = false;
        };

        runtimeInputs = with pkgs; [ libargon2 openssl ];

        script = ''
          ADMIN_TOKEN=$(cat "$prompts/admin-token" | argon2 "$(openssl rand -base64 32)" -e -id -k 19456 -t 2 -p 1)
          echo "ADMIN_TOKEN=$ADMIN_TOKEN" > "$out/vaultwarden-env"
        '';
      };

      
    };
  };
}
