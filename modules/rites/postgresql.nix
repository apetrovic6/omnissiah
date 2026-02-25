{self, ...}: {
  flake.nixosModules.postgresql = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption mkIf mkForce types mapAttrsToList mapAttrs' nameValuePair flatten;
    cfg = config.services.imperium.postgresql;
  in {
    options.services.imperium.postgresql = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Imperium PostgreSQL server with declarative user password management.";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Port for PostgreSQL to listen on.";
      };

      listenAddresses = mkOption {
        type = types.str;
        default = "localhost";
        description = "Addresses PostgreSQL listens on. Use \"*\" for all interfaces.";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Open the PostgreSQL port in the firewall.";
      };

      authentication = mkOption {
        type = types.lines;
        default = ''
          # TYPE  DATABASE  USER      ADDRESS         METHOD
          local   all       all                       peer
          host    all       all       127.0.0.1/32    scram-sha-256
          host    all       all       ::1/128         scram-sha-256
        '';
        description = "PostgreSQL pg_hba.conf authentication rules.";
      };

      backup = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable daily PostgreSQL backups via pg_dump.";
        };

        location = mkOption {
          type = types.str;
          default = "/var/backup/postgresql";
          description = "Directory to store backup files.";
        };

        startAt = mkOption {
          type = types.str;
          default = "*-*-* 03:00:00";
          description = "Systemd calendar expression for when to run backups.";
        };
      };

      users = mkOption {
        description = "PostgreSQL users with sops-managed passwords.";
        default = {};
        type = types.attrsOf (types.submodule ({name, ...}: {
          options = {
            databases = mkOption {
              type = types.listOf types.str;
              default = [name];
              description = "Databases to ensure exist for this user.";
            };

            ensureDBOwnership = mkOption {
              type = types.bool;
              default = false;
              description = "Grant ownership of the user's databases.";
            };
          };
        }));
      };
    };

    config = mkIf (cfg.enable && cfg.users != {}) {
      services.postgresql = {
        enable = true;

        ensureDatabases = flatten (mapAttrsToList (_: u: u.databases) cfg.users);

        ensureUsers = mapAttrsToList (name: u: {
          inherit name;
          inherit (u) ensureDBOwnership;
        }) cfg.users;

        settings = {
          inherit (cfg) port;
          listen_addresses = mkForce cfg.listenAddresses;
          log_connections = true;
        };

        authentication = cfg.authentication;
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];

      services.postgresqlBackup = mkIf cfg.backup.enable {
        enable = true;
        location = cfg.backup.location;
        startAt = cfg.backup.startAt;
      };

      # One clan vars generator per user for password management
      clan.core.vars.generators =
        mapAttrs' (
          userName: _:
            nameValuePair "postgresql-${userName}" {
              share = false;

              files.password = {
                secret = true;
                owner = "postgres";
                group = "postgres";
                mode = "0400";
              };

              prompts.password = {
                description = "PostgreSQL password for user '${userName}'";
                type = "hidden";
                persist = true;
                display.label = "PostgreSQL password (${userName})";
              };

              script = ''
                cp "$prompts/password" "$out/password"
              '';
            }
        )
        cfg.users;

      # Single systemd service that sets all user passwords from sops secrets
      systemd.services.postgresql-password-init = {
        description = "Set PostgreSQL user passwords from sops secrets";
        after = ["postgresql.service" "postgresql-setup.service"];
        requires = ["postgresql.service" "postgresql-setup.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
        };
        script = let
          psql = "${config.services.postgresql.package}/bin/psql";
          commands = mapAttrsToList (userName: _: let
            passwordFile = config.clan.core.vars.generators."postgresql-${userName}".files.password.path;
          in ''
            echo "Setting password for user '${userName}'..."
            PASSWORD=$(cat "${passwordFile}")
            ${psql} -c "ALTER USER \"${userName}\" WITH PASSWORD '$PASSWORD';"
          '') cfg.users;
        in ''
          set -euo pipefail
          ${builtins.concatStringsSep "\n" commands}
        '';
      };
    };
  };
}
