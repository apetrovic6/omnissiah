{self, ...}: {
  flake.nixosModules.postgresql = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption mkPackageOption mkIf mkForce mkMerge types mapAttrsToList mapAttrs' nameValuePair flatten;
    cfg = config.services.imperium.postgresql;

    # For every role with readOnlyAccess: allow it into its databases from its
    # addresses, then reject everything else it tries.
    readOnlyHba = lib.concatStringsSep "\n" (flatten (mapAttrsToList (
        name: u:
          lib.optionals (u.readOnlyAccess != {}) (
            flatten (mapAttrsToList (
                db: ro:
                  map (addr: "host ${db} ${name} ${addr} scram-sha-256") ro.addresses
              )
              u.readOnlyAccess)
            # The role's own databases (none for a pure reader) stay reachable.
            ++ flatten (map (
                db:
                  map (addr: "host ${db} ${name} ${addr} scram-sha-256")
                  (lib.unique (flatten (mapAttrsToList (_: ro: ro.addresses) u.readOnlyAccess)))
              )
              u.databases)
            ++ ["local all ${name} reject" "host all ${name} all reject"]
          )
      )
      cfg.users));
  in {
    options.services.imperium.postgresql = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Imperium PostgreSQL server with declarative user password management.";
      };
      package = mkPackageOption pkgs "postgresql" {};

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

        retention = mkOption {
          type = types.int;
          default = 7;
          description = "Number of days to keep backups. Older backups are automatically deleted.";
        };

        databases = mkOption {
          type = types.listOf types.str;
          default = lib.unique (flatten (mapAttrsToList (_: u: u.databases) cfg.users));
          description = "List of databases to backup. Defaults to all databases managed by imperium users.";
        };
      };

      extensions = mkOption {
        type = types.attrsOf (types.functionTo types.package);
        default = {};
        description = ''
          Extensions to install and enable in every managed database.
          The attribute name is the SQL extension name used in CREATE EXTENSION;
          the value is a function that selects the package from the PostgreSQL
          package set (same argument as services.postgresql.extensions).
        '';
        example = lib.literalExpression ''
          {
            vector  = ps: ps.pgvector;
            postgis = ps: ps.postgis;
          }
        '';
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

            passwordDependency = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Name of another generator whose `password` file to use instead of
                prompting. When set, no prompt is created for this user; the password
                is copied from `$in/<passwordDependency>/password` at generation time.
              '';
            };

            generatePassword = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Generate a random password instead of prompting for one. For users that only
                connect over the socket with peer auth, where nothing ever types the password.
              '';
            };

            readOnlyAccess = mkOption {
              description = ''
                Databases this role may read but not change, keyed by database name.
                The role gets CONNECT on the database, USAGE on its `public` schema and
                SELECT on every table in it, including tables created LATER by the
                database's owner role: that is done with ALTER DEFAULT PRIVILEGES
                FOR ROLE <owner>, so it keeps working when an application creates or
                migrates its own tables after the grants ran (Blocky does exactly
                that on first start). Nothing else is granted: no INSERT/UPDATE/
                DELETE/TRUNCATE, no CREATE. Re-applied on every
                postgresql-password-init run, so it also catches tables that exist
                already. Use with `databases = []` for a role that owns nothing.

                Postgres lets PUBLIC connect to every database by default, so grants
                alone do not keep the role out of other databases (it could read their
                catalogs). Therefore pg_hba lines are generated and put AHEAD of
                `authentication`: the role may log in only to the databases listed
                here (plus its own `databases`), only from each entry's `addresses`,
                and every other host/local login by it is rejected.
              '';
              default = {};
              type = types.attrsOf (types.submodule {
                options.owner = mkOption {
                  type = types.str;
                  description = "The role that creates the tables in this database (the application's role).";
                };
                options.addresses = mkOption {
                  type = types.listOf types.str;
                  default = ["127.0.0.1/32" "::1/128"];
                  description = "CIDRs the role may connect from (pg_hba, scram-sha-256). Narrower than your generic rules on purpose: these lines come first.";
                };
                options.revokePublicTemp = mkOption {
                  type = types.bool;
                  default = false;
                  description = "REVOKE TEMP ON DATABASE FROM PUBLIC, so the role cannot create temp tables. Affects every role in that database that relied on the PUBLIC default; leave off for shared databases.";
                };
              });
              example = {blocky.owner = "blocky";};
            };

            extensions = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "SQL extension names to CREATE EXTENSION IF NOT EXISTS in each of this user's databases. The corresponding packages must be declared in services.imperium.postgresql.extensions.";
              example = ["vchord" "pg_trgm"];
            };
          };
        }));
      };
    };

    config = mkIf (cfg.enable && cfg.users != {}) {
      services.postgresql = {
        enable = true;

        extensions = ps: mapAttrsToList (_: f: f ps) cfg.extensions;

        ensureDatabases = lib.unique (flatten (mapAttrsToList (_: u: u.databases) cfg.users));

        ensureUsers =
          mapAttrsToList (name: u: {
            inherit name;
            inherit (u) ensureDBOwnership;
          })
          cfg.users;

        settings = {
          inherit (cfg) port;
          listen_addresses = mkForce cfg.listenAddresses;
          log_connections = true;
        };

        # pg_hba is first-match: the pins for read-only roles go first, ahead of
        # whatever generic rules `authentication` has (e.g. "host all all <lan>").
        authentication = lib.mkMerge [(lib.mkBefore readOnlyHba) cfg.authentication];
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];

      systemd.tmpfiles.rules = mkIf cfg.backup.enable [
        "d ${cfg.backup.location} 0750 postgres postgres -"
      ];

      systemd.services = mkMerge [
        (mkIf cfg.backup.enable (builtins.listToAttrs (map (db: let
          pg_dump = "${config.services.postgresql.package}/bin/pg_dump";
        in
          nameValuePair "postgresqlBackup-${db}" {
            description = "PostgreSQL backup for ${db}";
            after = ["postgresql.service"];
            requires = ["postgresql.service"];
            serviceConfig = {
              Type = "oneshot";
              User = "postgres";
              Group = "postgres";
            };
            script = ''
              set -euo pipefail
              mkdir -p "${cfg.backup.location}"
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              ${pg_dump} -Fc "${db}" > "${cfg.backup.location}/${db}-$TIMESTAMP.dump"

              # Remove backups older than ${toString cfg.backup.retention} days
              ${pkgs.findutils}/bin/find "${cfg.backup.location}" \
                -name "${db}-*.dump" \
                -mtime +${toString cfg.backup.retention} \
                -delete
            '';
          })
        cfg.backup.databases)))

        {
          postgresql-password-init = {
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
              commands =
                mapAttrsToList (userName: u: let
                  passwordFile = config.clan.core.vars.generators."postgresql-${userName}".files.password.path;
                  extCmds = flatten (map (
                      db:
                        map (ext: ''
                          echo "Creating extension '${ext}' in database '${db}'..."
                          ${psql} -d "${db}" -c "CREATE EXTENSION IF NOT EXISTS \"${ext}\" CASCADE;"
                        '')
                        u.extensions
                    )
                    u.databases);
                  roCmds =
                    mapAttrsToList (db: ro: ''
                      echo "Granting '${userName}' read-only access to '${db}' (tables of '${ro.owner}')..."
                      # A failing grant must not stop the users after this one: log it
                      # loudly, carry on, and fail the unit at the end (see `failed`).
                      {
                        ${psql} -d postgres -v ON_ERROR_STOP=1 \
                          -c "GRANT CONNECT ON DATABASE \"${db}\" TO \"${userName}\";" \
                          -c "${
                        if ro.revokePublicTemp
                        then "REVOKE TEMP ON DATABASE \\\"${db}\\\" FROM PUBLIC;"
                        else "SELECT 1;"
                      }" > /dev/null &&
                        ${psql} -d "${db}" -v ON_ERROR_STOP=1 \
                          -c "GRANT USAGE ON SCHEMA public TO \"${userName}\";" \
                          -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"${userName}\";" \
                          -c "ALTER DEFAULT PRIVILEGES FOR ROLE \"${ro.owner}\" IN SCHEMA public GRANT SELECT ON TABLES TO \"${userName}\";"
                      } || { echo "ERROR: read-only grant for '${userName}' on '${db}' FAILED" >&2; failed=1; }
                    '')
                    u.readOnlyAccess;
                in ''
                  echo "Setting password for user '${userName}'..."
                  PASSWORD=$(cat "${passwordFile}")
                  ${psql} -c "ALTER USER \"${userName}\" WITH PASSWORD '$PASSWORD';"
                  ${builtins.concatStringsSep "\n" roCmds}
                  ${builtins.concatStringsSep "\n" extCmds}
                '')
                cfg.users;
            in ''
              set -euo pipefail
              failed=0
              ${builtins.concatStringsSep "\n" commands}
              exit $failed
            '';
          };
        }
      ];

      systemd.timers = mkIf cfg.backup.enable (builtins.listToAttrs (map (
          db:
            nameValuePair "postgresqlBackup-${db}" {
              wantedBy = ["timers.target"];
              timerConfig = {
                OnCalendar = cfg.backup.startAt;
                Persistent = true;
              };
            }
        )
        cfg.backup.databases));

      # One clan vars generator per user for password management.
      # If passwordDependency is set, the password is sourced from another generator
      # (no prompt); with generatePassword it is random; otherwise a prompt is shown.
      clan.core.vars.generators =
        mapAttrs' (
          userName: u:
            nameValuePair "postgresql-${userName}" (
              if u.passwordDependency != null
              then {
                share = false;

                files.password = {
                  secret = true;
                  owner = "postgres";
                  group = "postgres";
                  mode = "0400";
                };

                dependencies = [u.passwordDependency];

                script = ''
                  cp "$in/${u.passwordDependency}/password" "$out/password"
                '';
              }
              else if u.generatePassword
              then {
                share = false;

                files.password = {
                  secret = true;
                  owner = "postgres";
                  group = "postgres";
                  mode = "0400";
                };

                runtimeInputs = [pkgs.openssl];

                # Hex, so it is safe inside the single-quoted ALTER USER in postgresql-password-init.
                script = ''
                  openssl rand -hex 32 | tr -d '\n' > "$out/password"
                '';
              }
              else {
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
        )
        cfg.users;
    };
  };
}
