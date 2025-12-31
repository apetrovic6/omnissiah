{...}: let
  ageKey = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
  fileNameRpc = "garage-rpc-secret";
  fileNameAdmin = "garage-ui-admin-token";
  fileNameGarageUiJwtSecret = "garage-ui-jwt-token-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileNameRpc} = {
      share = true;

      files.${fileNameRpc}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileNameRpc}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileNameRpc}
          namespace: garage
        spec:
          secretTemplates:
            - name: ${fileNameRpc}
              type: Opaque
              stringData:
                rpcSecret: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${fileNameAdmin} = {
      share = true;

      prompts.admin-token = {
        description = "Enter Garage admin token: ";
        type = "hidden";
        persist = false;
      };

      files.${fileNameAdmin}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

                secret="$(tr -d '\r\n' < "$prompts/admin-token")"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileNameAdmin}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileNameAdmin}
          namespace: garage
        spec:
          secretTemplates:
            - name: ${fileNameAdmin}
              type: Opaque
              stringData:
                admin-token: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${fileNameGarageUiJwtSecret} = {
      share = true;

      files.${fileNameGarageUiJwtSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

 script = ''
    set -euo pipefail

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    # Preserve PEM formatting by writing to a file
    openssl genpkey -algorithm ED25519 -out "$tmp/jwt-key.pem"

    sops encrypt \
      --age "${ageKey}" \
      --encrypted-suffix "Templates" \
      --input-type yaml --output-type yaml \
      /dev/stdin > "$out/${fileNameGarageUiJwtSecret}" <<EOF
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: ${fileNameGarageUiJwtSecret}
  namespace: garage
spec:
  secretTemplates:
    - name: ${fileNameGarageUiJwtSecret}
      type: Opaque
      stringData:
        jwt-key.pem: |-
$(sed 's/^/          /' "$tmp/jwt-key.pem")
EOF
  '';
    };
  };
}
