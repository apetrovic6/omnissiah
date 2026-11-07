# Credentials for the shared sccache compilation cache: the `sccache` bucket on
# the `garage-main` Garage cluster.
#
# The cache serves cargo builds that run OUTSIDE the Nix sandbox -- the user's
# workstations (and the agent worktrees on them) and the Forgejo runners' host
# steps. Nix builds stay as they are, cached by ncps; nothing here touches them,
# and generated products (rust-app-template) deliberately do not depend on this
# Garage: their devenv.nix knows nothing about sccache.
#
# Same inverted flow as rke2/kube-secrets/{kaneo,memos}, but it lives here
# rather than under taghmata/rke2/kube-secrets because the machines that need
# the credentials do not all import the noosphere module: luna and sol are
# k8s-base (no noosphere import) and the workstations are not servers at all.
# Every machine that enables this module gets the generator, so the clan var is
# deployed to all of them. The key pair is minted by the var and IMPORTED into
# Garage via `GarageKey.spec.importKey.secretRef` (see
# nixidy/_env/apps/garage-operator/cluster-main/default.nix), so the machines
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

          exec ${pkgs.sccache}/bin/sccache "$@"
        '';
        defaultText = lib.literalExpression ''
          writeShellScriptBin "sccache" -- unsets CARGO_INSTALL_ROOT and the
          ambient AWS_* credential vars, defaults AWS_SHARED_CREDENTIALS_FILE
          to the machine's clan var file, execs pkgs.sccache
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
