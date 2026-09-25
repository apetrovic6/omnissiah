# davical-go — CalDAV/CardDAV server (Go rewrite of DAViCal).
#
# The OCI image is built from source by this flake (see services/davical/,
# flake output .#davical-go-image) — there is no registry to pull from, so a
# oneshot loads the tarball into Podman before the container starts.
#
# Database: cerberus's existing Postgres (services.imperium.postgresql, set up
# in stc/server.nix), same pattern as kaneo.nix / nopresh.nix: the
# davical-secrets generator below produces the password (handed to Postgres via
# passwordDependency, so the two can never drift) and the container env file.
# The container uses --network=host because pg_hba.conf only allows
# 127.0.0.1/32 and 192.168.1.0/24 — the podman bridge (10.88.0.0/16) is not in
# it. davicald binds loopback only and Caddy fronts it with TLS.
{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;

  # 8080 is taken on cerberus by the Dagger engine container (./dagger.nix).
  port = 8081;

  # Literal value (no trailing newline) — davicald embeds it in set-password
  # links, so it needs the real string, not the {$LAB_DOMAIN} placeholder.
  baseDomain = lib.removeSuffix "\n" config.clan.core.vars.generators."caddy-env".files."domain".value;

  davical-go = self.packages.${pkgs.system}.davical-go;
  davical-image = self.packages.${pkgs.system}.davical-go-image;

  # `podman load` names the image `localhost/<name>:<tag>` — see services/davical/README.md.
  imageName = "localhost/davical-go:${davical-go.version}";

  envFile = config.clan.core.vars.generators."davical-secrets".files."davical.env".path;

  # The image has no shell, only the four static binaries; the admin and cron
  # one-shots reuse the same image with --entrypoint pointing at a different
  # one. Single-line so it can be interpolated into `if …; then` in scripts.
  podmanRun = entrypoint: args:
    ''${config.virtualisation.podman.package}/bin/podman run --rm --network=host --env-file ${envFile} --entrypoint ${entrypoint} ${imageName} ${args}'';
in {
  # Podman is already enabled on cerberus by ./nopresh.nix (which is the only
  # module that may import self.nixosModules.virtualisation — importing it a
  # second time fails with "option already declared").

  # Database — merges into services.imperium.postgresql from stc/server.nix.
  # Also enrols `davical` in the nightly pg_dump (backup.databases defaults to
  # every managed database).
  services.imperium.postgresql.users.davical = {
    databases = ["davical"];
    ensureDBOwnership = true;
    passwordDependency = "davical-secrets";
  };

  # Auto-generated, no prompts: the DB password (also consumed by Postgres via
  # the `password` file) and SECRET_KEY (set-/forgot-password tokens; rotating
  # it invalidates outstanding tokens). Hex only — a password containing
  # @ / % breaks the DATABASE URL parsing (as everywhere else on this host).
  clan.core.vars.generators.davical-secrets = {
    files."password" = {secret = true;};
    files."davical.env" = {
      secret = true;
      mode = "0400";
    };
    runtimeInputs = with pkgs; [coreutils openssl];
    # OWNER_DSN intentionally unset: davical owns the database
    # (ensureDBOwnership), so `db init` runs in single-role mode.
    script = ''
      DB_PASSWORD="$(openssl rand -hex 24)"
      SECRET_KEY="$(openssl rand -hex 32)"
      printf '%s' "$DB_PASSWORD" > "$out/password"
      cat > "$out/davical.env" <<EOF
      DATABASE=postgres://davical:$DB_PASSWORD@127.0.0.1:5432/davical?sslmode=disable
      SECRET_KEY=$SECRET_KEY
      EOF
    '';
  };

  # Load the Nix-built image tarball into Podman (idempotent: only loads when
  # the exact version tag is missing, so bumping davical-go.version in
  # services/davical/package.nix and redeploying picks the new image up).
  systemd.services.davical-image-load = {
    description = "Load the Nix-built davical-go image into Podman";
    after = ["podman.service"];
    wants = ["podman.service"];
    wantedBy = ["podman-davical.service"];
    before =
      [
        "podman-davical.service"
        "davical-db-init.service"
      ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${config.virtualisation.podman.package}/bin/podman image inspect ${imageName} >/dev/null 2>&1; then
        ${config.virtualisation.podman.package}/bin/podman load -i ${davical-image}
      fi
    '';
  };

  # One-shot schema bootstrap (the DDL is embedded in davical-admin). Runs
  # `db status` first so re-deploys are no-ops instead of failing on an
  # existing schema.
  systemd.services.davical-db-init = {
    description = "Bootstrap the DAViCal database schema if needed";
    after = [
      "network-online.target"
      "postgresql.service"
      "postgresql-password-init.service"
      "davical-image-load.service"
    ];
    wants = ["network-online.target"];
    requiredBy = ["podman-davical.service"];
    before = ["podman-davical.service"];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    # Neither davical-admin exit code can be trusted here, so Postgres is the
    # only honest gate — to_regclass is NULL until the schema is loaded:
    #   - `db status` exits 0 even when it reports "Schema: not initialised".
    #     The obvious `if db status; then …` gate therefore never bootstrapped
    #     anything: the unit logged "schema present and current" against a
    #     completely empty database, and every admin command failed with
    #     `ERROR: relation "usr" does not exist (SQLSTATE 42P01)`.
    #   - `db init` exits 1 when it finds an existing schema — *including the
    #     one it has just loaded itself*: on the empty database it created
    #     public.usr and then still exited 1 with "already has a DAViCal
    #     schema; use 'db upgrade'".
    # `db upgrade` is a clean no-op ("Already up to date at schema revision
    # 1.4.0"), so it is safe to run on every activation and keeps the schema in
    # step with davical-go.version bumps in services/davical/package.nix.
    script = ''
      set -a
      . ${envFile}
      set +a

      schemaPresent() {
        [ "$(${config.services.postgresql.package}/bin/psql "$DATABASE" -tAc \
              "select to_regclass('public.usr') is not null")" = t ]
      }

      if ! schemaPresent; then
        echo "Schema missing — running db init."
        ${podmanRun "/davical-admin" "db init"} || true
        if ! schemaPresent; then
          echo "db init did not create the schema — giving up." >&2
          exit 1
        fi
      fi

      ${podmanRun "/davical-admin" "db status"}
      ${podmanRun "/davical-admin" "db upgrade"}
    '';
  };

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.davical = {
    # No registry: loaded from the Nix tarball by davical-image-load.service.
    # (No io.containers.autoupdate label — podman auto-update would not find it.)
    image = imageName;
    autoStart = true;
    # Host networking so the container reaches Postgres on 127.0.0.1:5432
    # (the podman bridge is not in pg_hba.conf). No `ports` — with host
    # networking davicald binds loopback itself via LISTEN.
    extraOptions = ["--network=host"];
    environment = {
      # Loopback only; TLS terminates in Caddy below.
      LISTEN = "127.0.0.1:${toString port}";
      TZ = "Europe/Zagreb";
      SERVER_DISPLAYNAME = "UGALA CalDAV";
      ENABLE_SCHEDULING = "true";
      ENABLE_AUTO_SCHEDULE = "true";
      # Externally visible base URL (no trailing slash), used in the
      # set-password / forgotten-password links under /adm/.
      BASE_URL = "https://dav.${baseDomain}";
      # SMTP unset -> outbound mail disabled (set-password emails are dropped).
    };
    environmentFiles = [envFile];
  };

  # Scheduled maintenance, as recommended by services/davical/README.md.
  systemd.services.davical-cron-refresh-alarms = {
    description = "DAViCal maintenance: refresh-alarms";
    after = ["network-online.target" "postgresql.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
    };
    script = podmanRun "/davical-cron" "refresh-alarms";
  };
  systemd.timers.davical-cron-refresh-alarms = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };

  # Fetches the IANA timezone database over HTTPS into the DB (the image ships
  # cacert + SSL_CERT_FILE, so the outbound TLS works).
  systemd.services.davical-cron-tz-update = {
    description = "DAViCal maintenance: tz-update";
    after = ["network-online.target" "postgresql.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
    };
    script = podmanRun "/davical-cron" "tz-update";
  };
  systemd.timers.davical-cron-tz-update = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # https://dav.<lab-domain> -> the container. LAN/VPN only (not in the
  # Pangolin blueprint, like kaneo/nopresh).
  services.caddy.virtualHosts."${mkDomain "dav"}".extraConfig =
    mkRevProxyVHost {inherit port;};
}
