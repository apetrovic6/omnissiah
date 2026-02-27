{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  name = "barman-s3-credentials";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${name} = {
      share = true;

      prompts.access-key-id = {
        description = "Enter Barman S3 Access Key ID: ";
        type = "line";
        persist = false;
      };

      prompts.access-key-secret = {
        description = "Enter Barman S3 Access Key Secret: ";
        type = "hidden";
        persist = false;
      };

      files.${name}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail
        access_key="$(tr -d '\r\n' < "$prompts/access-key-id")"
        secret_key="$(tr -d '\r\n' < "$prompts/access-key-secret")"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${name}" <<EOF
        access_key_id: "$access_key"
        access_secret_key: "$secret_key"
        EOF
      '';
    };
  };
}
