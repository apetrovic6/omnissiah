# S3 credentials for Kaneo's upload bucket on the `garage-main` cluster.
#
# Kaneo runs on cerberus, OUTSIDE the k8s cluster, so the usual flow (operator
# mints a key -> Secret -> reflector -> app namespace) does not reach it. This
# inverts it: the key pair is generated here and *imported* into Garage via
# `GarageKey.spec.importKey.secretRef` (see
# nixidy/_env/apps/garage-operator/cluster-main/default.nix), so both sides are
# fed from one clan var and nothing has to be copied by hand.
#
# Two outputs:
#   - kaneo-s3-key  (non-secret) sops-encrypted SopsSecret, read into the
#                   garage-operator app with builtins.readFile
#   - kaneo-s3.env  (secret)     env file for the container + CORS unit on
#                                cerberus, which gets this generator via the
#                                `server` tag -> stc/server.nix -> noosphere
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  fileName = "kaneo-s3-key";
  envFile = "kaneo-s3.env";
  # Name of the SopsSecret-backed Secret the operator imports FROM. Deliberately
  # not "kaneo": that is the GarageKey's own name, and the operator writes its
  # own Secret under that name.
  importSecret = "kaneo-s3-import";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileName} = {
      share = true;

      files.${fileName}.secret = false;
      files.${envFile} = {
        secret = true;
        mode = "0400";
      };

      runtimeInputs = [pkgs.coreutils pkgs.openssl pkgs.sops];

      script = ''
        set -euo pipefail

        # Garage's own format (src/model/key_table.rs): "GK" + 24 hex chars from
        # 12 random bytes, secret = 64 hex chars from 32 random bytes.
        access_key_id="GK$(openssl rand -hex 12)"
        secret_access_key="$(openssl rand -hex 32)"

        # Both spellings: S3_* is what Kaneo reads, AWS_* is what the aws CLI in
        # kaneo-s3-cors.service reads. One file serves both.
        cat > "$out/${envFile}" <<EOF
        S3_ACCESS_KEY_ID=$access_key_id
        S3_SECRET_ACCESS_KEY=$secret_access_key
        AWS_ACCESS_KEY_ID=$access_key_id
        AWS_SECRET_ACCESS_KEY=$secret_access_key
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
}
