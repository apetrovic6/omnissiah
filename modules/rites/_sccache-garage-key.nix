# Mint one Garage S3 key pair for both a host and the cluster import.
{
  lib,
  pkgs,
  ageKey,
  generatorName,
  importSecret,
}: {
  share = true;

  files.${generatorName}.secret = false;
  files.credentials = {
    secret = true;
    mode = "0400";
    # Root reads this through LoadCredential; only workstations override the owner.
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
    cat > "$out/credentials" <<EOF
    [default]
    aws_access_key_id = $access_key_id
    aws_secret_access_key = $secret_access_key
    EOF

    sops encrypt \
      --age "${ageKey}" \
      --encrypted-suffix "Templates" \
      --input-type yaml --output-type yaml \
      /dev/stdin > "$out/${generatorName}" <<EOF
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
}
