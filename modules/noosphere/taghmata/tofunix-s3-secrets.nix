{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  secretsFile = "tofunix-s3-secrets";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${secretsFile} = {
      share = true;

      files.${secretsFile}.secret = false;

      prompts.access-key-id = {
        description = "S3 access key ID for the opentofu Garage bucket";
        type = "line";
        persist = false;
      };

      prompts.secret-access-key = {
        description = "S3 secret access key for the opentofu Garage bucket";
        type = "hidden";
        persist = false;
      };

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        access_key_id="$(tr -d '\r\n' < "$prompts/access-key-id")"
        secret_access_key="$(tr -d '\r\n' < "$prompts/secret-access-key")"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretsFile}" <<EOF
        access_key_id: "$access_key_id"
        secret_access_key: "$secret_access_key"
        EOF
      '';
    };
  };
}
