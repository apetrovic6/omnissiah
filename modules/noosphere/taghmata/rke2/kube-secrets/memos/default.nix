# S3 credentials for Memos' attachment bucket on the `garage-main` cluster.
#
# Same inversion as kaneo (see ../kaneo/default.nix): Memos runs on cerberus,
# OUTSIDE the k8s cluster, so the operator-mints-a-key flow does not reach it.
# The key pair is generated here and *imported* into Garage via
# `GarageKey.spec.importKey.secretRef` (see
# nixidy/_env/apps/garage-operator/cluster-main/default.nix), so both sides are
# fed from one clan var and nothing has to be copied by hand.
#
# Three outputs:
#   - memos-s3-key                        (non-secret) sops-encrypted SopsSecret,
#                                         read into the garage-operator app with
#                                         builtins.readFile
#   - memos-s3.env                        (secret) env file for the CORS unit on
#                                         cerberus (aws CLI reads AWS_*)
#   - memos-instance-setting-storage.json (secret) memos 0.30 deployment-managed
#                                         configuration. memos no longer takes
#                                         S3 settings from the environment; it
#                                         loads validated protojson
#                                         InstanceSetting files from the
#                                         hardcoded /etc/secrets directory at
#                                         startup (store/deployment_config.go).
#                                         The file acts as a runtime override —
#                                         the Storage page in the UI/API stays
#                                         read-only while it is present.
#                                         cerberus gets this generator via the
#                                         `server` tag -> stc/server.nix ->
#                                         noosphere
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  domain = config.noosphere.domain;
  fileName = "memos-s3-key";
  envFile = "memos-s3.env";
  jsonFile = "memos-instance-setting-storage.json";
  # Name of the SopsSecret-backed Secret the operator imports FROM. Deliberately
  # not "memos": that is the GarageKey's own name, and the operator writes its
  # own Secret under that name.
  importSecret = "memos-s3-import";
  # Must be the PUBLIC ingress hostname, not the in-cluster Service: memos hands
  # out presigned GET URLs (5-day expiry) that the browser itself fetches.
  s3Endpoint = "https://s3.main.garage.${domain}";
  s3Bucket = "memos";
  # garage-main's s3Api.region (nixidy/_env/apps/garage-operator/cluster-main).
  s3Region = "main";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileName} = {
      share = true;

      files.${fileName}.secret = false;
      files.${envFile} = {
        secret = true;
        mode = "0400";
      };
      files.${jsonFile} = {
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

        # Both spellings: AWS_* is what the aws CLI in memos-s3-cors.service
        # reads; S3_* kept for symmetry with kaneo-s3.env.
        cat > "$out/${envFile}" <<EOF
        S3_ACCESS_KEY_ID=$access_key_id
        S3_SECRET_ACCESS_KEY=$secret_access_key
        AWS_ACCESS_KEY_ID=$access_key_id
        AWS_SECRET_ACCESS_KEY=$secret_access_key
        EOF

        # protojson of storepb.InstanceSetting, validated at startup by
        # validateAndNormalizeDeploymentInstanceSetting(): key STORAGE requires
        # storageSetting, and S3 requires accessKeyId/accessKeySecret/endpoint/
        # region/bucket to be non-empty. Filename must match
        # ^memos-instance-setting-[a-z0-9]+(-[a-z0-9]+)*\.json$.
        # Unknown or misspelled fields fail startup (DiscardUnknown: false), so
        # keep this in sync with the proto when upgrading memos.
        cat > "$out/${jsonFile}" <<EOF
        {
          "key": "STORAGE",
          "storageSetting": {
            "storageType": "S3",
            "filepathTemplate": "assets/{timestamp}_{uuid}_{filename}",
            "uploadSizeLimitMb": 200,
            "s3Config": {
              "accessKeyId": "$access_key_id",
              "accessKeySecret": "$secret_access_key",
              "endpoint": "${s3Endpoint}",
              "region": "${s3Region}",
              "bucket": "${s3Bucket}",
              "usePathStyle": true
            }
          }
        }
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
