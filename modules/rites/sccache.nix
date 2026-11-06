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
