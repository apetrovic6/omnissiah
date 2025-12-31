{...}: let
  ageKey = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
  fileName = "s3-longhorn-backup";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileName} = {
     share = true;

      prompts.access-key-id = {
        description = "Enter Access Key ID: ";
        type = "line";
        persist = false;
      };

      prompts.access-key-secret= {
        description = "Enter Access Key Secret: ";
        type = "hidden";
        persist = false;
      };

      prompts.endpoint= {
        description = "Enter s3 endpoint: ";
        type = "line";
        persist = false;
      };

      files.${fileName}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                access_key="$(tr -d '\r\n' < "$prompts/access-key-id")"
                secret_key="$(tr -d '\r\n' < "$prompts/access-key-secret")"
                endpoint="$(tr -d '\r\n' < "$prompts/endpoint")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileName}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: s3-backup-secret
          namespace: longhorn-system
        spec:
          secretTemplates:
            - name: s3-backup-secret
              type: Opaque
              stringData:
                AWS_ACCESS_KEY_ID: "$acess_key"
                AWS_SECRET_ACCESS_KEY: "$secret_key"
                AWS_ENDPOINTS: "$endpoint"
        EOF
      '';
    };
  };
}
