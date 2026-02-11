{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  fileNameJwtSecret = "garage-main-ui-jwt-token-secret";
  fileNameOidcSecret = "garage-main-ui-oidc-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileNameJwtSecret} = {
      share = true;

      files.${fileNameJwtSecret}.secret = false;

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
              /dev/stdin > "$out/${fileNameJwtSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileNameJwtSecret}
          namespace: garage-operator
        spec:
          secretTemplates:
            - name: ${fileNameJwtSecret}
              type: Opaque
              stringData:
                jwt-key.pem: |-
        $(sed 's/^/          /' "$tmp/jwt-key.pem")
        EOF
      '';
    };

    clan.core.vars.generators.${fileNameOidcSecret} = {
      share = true;

      prompts.client-secret = {
        description = "Keycloak Client Secret for Garage Main UI";
        type = "hidden";
        persist = false;
      };

      files.${fileNameOidcSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.jq];

      script = ''
        set -euo pipefail

        client_secret="$(tr -d '\r\n' < "$prompts/client-secret")"

        # Create the SopsSecret YAML using jq
        jq -n \
          --arg client_secret "$client_secret" \
          '{
            apiVersion: "isindir.github.com/v1alpha3",
            kind: "SopsSecret",
            metadata: {
              name: "garage-main-ui-oidc-secret",
              namespace: "garage-operator"
            },
            spec: {
              secretTemplates: [{
                name: "garage-main-ui-oidc-secret",
                type: "Opaque",
                stringData: {
                  "client-secret": $client_secret
                }
              }]
            }
          }' | sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type json --output-type yaml \
          /dev/stdin > "$out/${fileNameOidcSecret}"
      '';
    };
  };
}
