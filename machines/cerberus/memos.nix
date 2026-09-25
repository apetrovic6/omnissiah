# Memos — self-hosted, lightweight note-taking. Native NixOS service
# (nixos/modules/services/misc/memos.nix), not a container: memos is a single
# Go binary and the upstream module already ships a well-hardened unit.
#
# Database: cerberus's existing Postgres (services.imperium.postgresql, set up
# in stc/server.nix) rather than the module's default embedded SQLite — same
# pattern as kaneo.nix / davical.nix / nopresh.nix. The memos-secrets generator
# produces the password (handed to Postgres via passwordDependency, so the two
# can never drift) and the env file holding MEMOS_DSN.
#
# Reachable at https://memos.<lab-domain> via Caddy on the LAN/VPN only —
# deliberately NOT added to the Pangolin blueprint in ./configuration.nix.
#
# Attachment storage: the `memos` bucket on the garage-main cluster (k8s),
# same inverted flow as kaneo.nix — the key pair is minted by the shared
# `memos-s3-key` clan var (modules/noosphere/taghmata/rke2/kube-secrets/memos)
# and imported into Garage there, so both sides come from one source.
# Memos 0.30 no longer configures S3 through the environment: it loads
# validated protojson InstanceSetting files from the hardcoded /etc/secrets
# directory at startup (store/deployment_config.go). The generated JSON is
# installed there by memos-s3-config.service below; while it is present it
# overrides the DB and the Storage settings page is read-only in the UI.
{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;

  port = 5230;

  # The stored var keeps a trailing newline (caddy.nix writes it with `echo`),
  # which would corrupt the env file line and the instance URL. Caddy gets the
  # {$LAB_DOMAIN} runtime placeholder via mkDomain; memos needs the literal.
  baseDomain = lib.removeSuffix "\n" config.clan.core.vars.generators."caddy-env".files."domain".value;

  secretEnv = config.clan.core.vars.generators."memos-secrets".files."memos.env".path;

  # S3 attachment storage on garage-main, reached over its Traefik ingress.
  # Must be the PUBLIC hostname, not the in-cluster Service: memos stores
  # presigned GET URLs (5-day expiry) that the browser itself fetches.
  # Technitium resolves this to the MetalLB VIP directly, so it does not
  # hairpin through this machine's Caddy. Hardcoded like kaneo.nix: the
  # ingress lives on the noosphere.uk zone, NOT the Caddy LAB_DOMAIN
  # (baseDomain), and the value is baked into the generated JSON by
  # kube-secrets/memos/default.nix — keep the two in sync.
  s3Endpoint = "https://s3.main.garage.noosphere.uk";
  s3Bucket = "memos";
  s3Region = "main";
  clientUrl = "https://memos.${baseDomain}";

  s3EnvFile = config.clan.core.vars.generators."memos-s3-key".files."memos-s3.env".path;
  s3SettingJson = config.clan.core.vars.generators."memos-s3-key".files."memos-instance-setting-storage.json".path;

  # Attachment downloads are presigned GETs fetched by the browser from the
  # Garage origin, so the bucket must allow memos' origin. Uploads go through
  # the memos server (PutObject), so GET/HEAD is all the browser needs. The
  # GarageBucket CRD has no CORS field, so it is applied over the S3 API
  # instead (Garage implements PutBucketCors) — same workaround as kaneo.nix.
  corsConfig = pkgs.writeText "memos-cors.json" (builtins.toJSON {
    CORSRules = [
      {
        AllowedHeaders = ["*"];
        AllowedMethods = ["GET" "HEAD"];
        AllowedOrigins = [clientUrl];
        ExposeHeaders = ["ETag"];
        MaxAgeSeconds = 3000;
      }
    ];
  });
in {
  # Database — merges into services.imperium.postgresql from stc/server.nix.
  # Also enrols `memos` in the nightly pg_dump (backup.databases defaults to
  # every managed database).
  services.imperium.postgresql.users.memos = {
    databases = ["memos"];
    ensureDBOwnership = true;
    passwordDependency = "memos-secrets";
  };

  # Auto-generated, no prompts: the DB password (also consumed by Postgres via
  # the `password` file) and the DSN line built from it. Hex only — a password
  # containing @ / % breaks URL parsing in lib/pq (as everywhere else here).
  #
  # The DSN lives in a secret env file rather than in services.memos.settings
  # because the module renders `settings` into a world-readable nix store path
  # (`pkgs.formats.keyValue`), which would publish the password to every user
  # on the host.
  clan.core.vars.generators.memos-secrets = {
    files."password" = {secret = true;};
    files."memos.env" = {
      secret = true;
      mode = "0400";
    };
    runtimeInputs = with pkgs; [coreutils openssl];
    script = ''
      DB_PASSWORD="$(openssl rand -hex 24)"
      printf '%s' "$DB_PASSWORD" > "$out/password"
      cat > "$out/memos.env" <<EOF
      MEMOS_DSN=postgresql://memos:$DB_PASSWORD@127.0.0.1:5432/memos?sslmode=disable
      EOF
    '';
  };

  services.memos = {
    enable = true;

    # Left false on purpose: memos binds loopback and Caddy fronts it, and the
    # module's firewall branch references a nonexistent `cfg.port` — enabling
    # it would fail to evaluate.
    openFirewall = false;

    settings = {
      MEMOS_MODE = "prod";
      MEMOS_ADDR = "127.0.0.1";
      MEMOS_PORT = toString port;
      MEMOS_DATA = config.services.memos.dataDir;

      # Postgres instead of the module default of sqlite. MEMOS_DSN is *not*
      # set here — it carries the password and comes from the secret env file
      # layered on below.
      MEMOS_DRIVER = "postgres";

      # Externally visible base URL. Note this also flips memos' AllowAnonymous
      # check on (internal/profile/profile.go): unauthenticated visitors get the
      # public Explore view instead of a forced sign-in redirect. They still only
      # see memos explicitly marked public, and this host is LAN/VPN-only.
      MEMOS_INSTANCE_URL = "https://memos.${baseDomain}";
    };
  };

  # The module sets EnvironmentFile to the single generated (store) file. Layer
  # the secret file after it so MEMOS_DSN is defined without ever entering the
  # store; later EnvironmentFile entries win on conflict.
  systemd.services.memos = {
    after = [
      "postgresql.service"
      "postgresql-password-init.service"
      "memos-s3-config.service"
    ];
    wants = [
      "postgresql.service"
      "postgresql-password-init.service"
      "memos-s3-config.service"
    ];
    serviceConfig.EnvironmentFile = lib.mkForce [
      config.services.memos.environmentFile
      secretEnv
    ];
  };

  # Memos 0.30 loads deployment-managed instance settings from the hardcoded
  # /etc/secrets directory (store/deployment_config.go) — the filename must
  # match ^memos-instance-setting-[a-z0-9]+(-[a-z0-9]+)*\.json$. The generated
  # JSON carries the S3 access key, so it lives in the sops-nix secret store
  # (root, 0400) and is installed here, owned by the service user. Idempotent:
  # re-copied on every boot, which also self-heals key rotation after a
  # `clan vars generate` + rebuild + memos restart.
  systemd.services.memos-s3-config = {
    description = "Install the memos S3 deployment configuration into /etc/secrets";
    before = ["memos.service"];
    after = ["local-fs.target"];
    wantedBy = ["memos.service"];
    unitConfig.ConditionPathExists = s3SettingJson;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -D -m 0400 -o ${config.services.memos.user} -g ${config.services.memos.group} ${s3SettingJson} /etc/secrets/memos-instance-setting-storage.json";
    };
  };

  # Apply the bucket CORS policy before the app starts. PutBucketCors is
  # idempotent, so re-running on every boot is safe and self-healing.
  systemd.services.memos-s3-cors = {
    description = "Apply CORS policy to the Memos Garage bucket";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    before = ["memos.service"];
    wantedBy = ["memos.service"];
    path = [pkgs.awscli2];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = s3EnvFile;
      # The bucket is created by garage-operator on the cluster; if ArgoCD has
      # not synced yet, retry rather than leaving the app without CORS.
      Restart = "on-failure";
      RestartSec = "30s";
    };
    environment.AWS_REGION = s3Region;
    # Same workaround the cluster applies for Garage in
    # _modules/templates/garage-object-store.nix — modern AWS SDKs send
    # checksum trailers Garage rejects.
    environment.AWS_REQUEST_CHECKSUM_CALCULATION = "when_required";
    environment.AWS_RESPONSE_CHECKSUM_VALIDATION = "when_required";
    script = ''
      aws --endpoint-url ${s3Endpoint} s3api put-bucket-cors \
        --bucket ${s3Bucket} \
        --cors-configuration "file://${corsConfig}"
    '';
  };

  # https://memos.<lab-domain> -> the service. LAN/VPN only.
  services.caddy.virtualHosts."${mkDomain "memos"}".extraConfig =
    mkRevProxyVHost {inherit port;};
}
