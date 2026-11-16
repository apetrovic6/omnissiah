# Credentials for the shared sccache compilation cache: the `sccache` bucket on
# the `garage-main` Garage cluster.
#
# The cache serves cargo builds that run OUTSIDE the Nix sandbox -- the user's
# workstations (and the agent worktrees on them) and the Forgejo runners' host
# steps. Nix builds stay as they are, cached by ncps; nothing here touches them,
# and generated products (rust-app-template) deliberately do not depend on this
# Garage: their devenv.nix knows nothing about sccache.
#
# Same inverted flow as reliquary/{kaneo,memos}, but it lives here
# rather than under taghmata/reliquary because the machines that need the
# credentials are not all cluster nodes: the workstations use it too.
# Every machine that enables this module gets the generator, so the clan var is
# deployed to all of them. The key pair is minted by the var and IMPORTED into
# Garage via `GarageKey.spec.importKey.secretRef` (see
# nixidy/_env/apps/datavault/garage-operator/cluster-main/default.nix), so the machines
# and Garage are fed from one source and nothing is copied by hand.
#
# Two outputs:
#   - sccache-garage-key  (non-secret) sops-encrypted SopsSecret, read into the
#                         garage-operator app with builtins.readFile
#   - credentials         (secret)     AWS shared-credentials-format file
#                         ([default] profile), which is what sccache 0.19's S3
#                         backend (opendal -> reqsign) reads through
#                         AWS_SHARED_CREDENTIALS_FILE. Root-owned by default:
#                         the runner services read it as root through systemd
#                         LoadCredential (their DynamicUser cannot own files).
#                         stc/workstation.nix overrides the owner to apetrovic
#                         so the user's sccache server can read it directly.
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  domain = config.noosphere.domain;
  generatorName = "sccache-garage-key";
  fileName = "sccache-garage-key";
  credentialsFile = "credentials";
  # Name of the SopsSecret-backed Secret the operator imports FROM. Deliberately
  # not "sccache": that is the GarageKey's own name, and the operator writes its
  # own Secret under that name.
  importSecret = "sccache-s3-import";
in {
  flake.nixosModules.sccache = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.imperium.sccache;
  in {
    options.services.imperium.sccache = {
      enable = lib.mkEnableOption "credentials for the shared sccache bucket on garage-main";

      # Read-only knobs: every consumer (forgejo-runner.nix, the workstation
      # home-manager config) takes its values from here so the machines and the
      # bucket cannot drift apart.
      bucket = lib.mkOption {
        type = lib.types.str;
        default = "sccache";
        readOnly = true;
        description = "GarageBucket name on garage-main that holds the cache objects.";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "https://s3.main.garage.${domain}";
        readOnly = true;
        description = ''
          S3 endpoint (LAN VIP through Traefik; LAN/VPN only, no Pangolin route).
          The scheme is part of the value: sccache's endpoint resolver defaults a
          scheme-less endpoint to HTTP.
        '';
      };
      region = lib.mkOption {
        type = lib.types.str;
        default = "main";
        readOnly = true;
        description = "S3 region; garage-main's s3Api.region.";
      };

      # The only `sccache` binary consumers should ever invoke: a wrapper
      # around pkgs.sccache that scrubs the two classes of environment
      # pollution that break the shared cache (per-checkout CARGO_* in every
      # cache key; ambient AWS_* beating the credentials file). Defined once
      # here so the runners (forgejo-runner.nix) and the workstations
      # (stc/workstation.nix, users/apetrovic/home-configuration.nix) cannot
      # drift apart, and shipped under the name `sccache` so that no plain
      # invocation on any PATH can bypass it.
      wrapper = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = pkgs.writeShellScriptBin "sccache" ''
          # 1. Cache keys. sccache 0.19 hashes EVERY CARGO_* env var of the
          #    client process verbatim into the Rust key (compiler/rust.rs;
          #    the client snapshots its own environment in cmdline.rs and
          #    sends it with the compile request -- the wrapper IS the client
          #    process, so unsetting here really removes it from the key).
          #    devenv's languages.rust exports
          #    CARGO_INSTALL_ROOT=<project>/.devenv/state/cargo-install, and
          #    CI jobs run `devenv shell` in per-job act work dirs, so
          #    without this unset every key carries the checkout path and
          #    nothing is shared between worktrees or jobs. rustc never reads
          #    CARGO_INSTALL_ROOT -- it only steers where `cargo install`
          #    puts binaries, which happens in the shell, not through the
          #    wrapper -- so dropping it on the rustc side is safe.
          unset CARGO_INSTALL_ROOT

          # 2. Credential chain. reqsign's default AWS chain (via opendal)
          #    is env -> profile -> sso -> web-identity -> process -> ecs ->
          #    imds: AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the ambient
          #    environment (e.g. the tofunix S3 key from the omnissiah
          #    .envrc) BEAT the AWS_SHARED_CREDENTIALS_FILE profile the
          #    server is supposed to use, and server startup then fails
          #    ("refreshed signing credential expires before the requested
          #    operation deadline"). That failure is NOT covered by
          #    SCCACHE_IGNORE_SERVER_IO_ERROR -- it only downgrades IO errors
          #    while talking to an already-running server -- so every cargo
          #    build fails hard, and a server that does come up with the
          #    wrong env keeps serving every later client on
          #    127.0.0.1:4226 until its idle timeout. AWS_PROFILE goes too:
          #    the credentials file has only [default], and a foreign profile
          #    would send the profile provider looking for a section that
          #    does not exist, falling through the rest of the chain.
          unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

          # 3. Credentials. Keep an AWS_SHARED_CREDENTIALS_FILE that is
          #    already set (the runners hand it to the unit through systemd
          #    LoadCredential + Environment=; the wrapper never unsets it);
          #    otherwise fall back to this machine's deployed clan var file
          #    (the workstations: user-owned there, and the sccache server
          #    opens it directly). Scoped to sccache's own process tree -- a
          #    session-wide export would redirect the aws CLI and every AWS
          #    SDK tool to a key that can see exactly one bucket.
          export AWS_SHARED_CREDENTIALS_FILE="''${AWS_SHARED_CREDENTIALS_FILE:-${config.clan.core.vars.generators.${generatorName}.files.${credentialsFile}.path}}"

          # 4. Garage unreachable = uncached, never a failed build (RT-77).
          #    sccache 0.19 runs a storage check (`.sccache_check` GET)
          #    when it starts its server. If that check fails, every
          #    compile fails with "Server startup failed", and
          #    SCCACHE_IGNORE_SERVER_IO_ERROR does not cover it (it only
          #    covers IO errors against a server that is already up).
          #    Measured against `cargo build -p xtask` in
          #    rust-app-template: refused endpoint rc=101 after 0 s,
          #    black-holed endpoint rc=101 after the 10 s startup timeout.
          #    SCCACHE_SKIP_CACHE_CHECK=1 is not the fix: it starts the
          #    server, but against a black hole each lookup waits out the
          #    60 s lookup timeout (646 s against 15 s).
          #
          #    So, for a compiler invocation (the first argument is not an
          #    sccache flag) with no server listening, start the server
          #    here. If that fails, run the compiler directly and leave a
          #    marker so that the next 5 minutes of rustc invocations go
          #    straight to the compiler instead of paying the startup
          #    timeout each time. A server that is already listening is
          #    trusted: once it is up, a storage error is a cache miss and
          #    the compile runs locally (sccache's own CacheReadError path).
          #    Still uncovered: Garage starting to hang after a server came
          #    up. That's slow (up to the 60 s lookup timeout per unit), and
          #    long enough to reach a job timeout. Also skipped entirely: a
          #    server on a Unix socket (SCCACHE_SERVER_UDS), which nothing
          #    here uses, because /dev/tcp can't probe one. The port is
          #    resolved the way sccache does it (commands.rs, get_addr): a
          #    value that isn't a number means 4226, so a garbage
          #    SCCACHE_SERVER_PORT can't make the probe miss a live server.
          if [ "$#" -gt 0 ] && [ "''${1#-}" = "$1" ] && [ -z "''${SCCACHE_SERVER_UDS:-}" ]; then
            port="''${SCCACHE_SERVER_PORT:-4226}"
            case "$port" in "" | *[!0-9]*) port=4226 ;; esac
            [ "''${#port}" -le 5 ] && [ "$port" -le 65535 ] || port=4226
            listening() { (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; }
            if ! listening; then
              marker="''${TMPDIR:-/tmp}/sccache-unavailable-$(${pkgs.coreutils}/bin/id -u)-$port"
              if [ -n "$(${pkgs.findutils}/bin/find "$marker" -mmin -5 2>/dev/null)" ]; then
                exec "$@"
              fi
              if ! ${pkgs.sccache}/bin/sccache --start-server >/dev/null 2>&1 && ! listening; then
                ${pkgs.coreutils}/bin/touch "$marker" 2>/dev/null || true
                echo "sccache: cache storage unreachable, compiling locally for the next 5 minutes" >&2
                exec "$@"
              fi
              ${pkgs.coreutils}/bin/rm -f "$marker"
            fi
          fi

          exec ${pkgs.sccache}/bin/sccache "$@"
        '';
        defaultText = lib.literalExpression ''
          writeShellScriptBin "sccache" -- unsets CARGO_INSTALL_ROOT and the
          ambient AWS_* credential vars, defaults AWS_SHARED_CREDENTIALS_FILE
          to the machine's clan var file, runs the compiler directly when the
          sccache server cannot start (Garage unreachable), execs pkgs.sccache
        '';
        description = ''
          Credentialed, cache-key-scrubbing sccache wrapper. Use this
          everywhere instead of the bare binary: as RUSTC_WRAPPER and as the
          `sccache` on PATH.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      clan.core.vars.generators.${generatorName} = {
        share = true;

        files.${fileName}.secret = false;
        files.${credentialsFile} = {
          secret = true;
          mode = "0400";
          # root everywhere by default (runners read it through systemd
          # LoadCredential, which runs as root); the workstations override to
          # the user, whose sccache server opens the file directly.
          owner = lib.mkDefault "root";
        };

        runtimeInputs = [pkgs.coreutils pkgs.openssl pkgs.sops];

        script = ''
          set -euo pipefail

          # Garage's own format (src/model/key_table.rs): "GK" + 24 hex chars from
          # 12 random bytes, secret = 64 hex chars from 32 random bytes.
          access_key_id="GK$(openssl rand -hex 12)"
          secret_access_key="$(openssl rand -hex 32)"

          # AWS shared-credentials format; reqsign's profile provider reads the
          # [default] profile (AWS_PROFILE unset) from whatever
          # AWS_SHARED_CREDENTIALS_FILE points at.
          umask 077
          cat > "$out/${credentialsFile}" <<EOF
          [default]
          aws_access_key_id = $access_key_id
          aws_secret_access_key = $secret_access_key
          EOF

          sops encrypt \
            --age "${ageKey}" \
            --encrypted-suffix "Templates" \
            --input-type yaml --output-type yaml \
            /dev/stdin > "$out/${fileName}" <<EOF
          apiVersion: isindir.github.com/v1alpha3
          kind: SopsSecret
          metadata:
            name: ${importSecret}
            namespace: garage-operator
          spec:
            secretTemplates:
              - name: ${importSecret}
                type: Opaque
                stringData:
                  access-key-id: "$access_key_id"
                  secret-access-key: "$secret_access_key"
          EOF
        '';
      };
    };
  };
}
