{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  garageUiOidcSecret = "garage-ui-oidc-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${garageUiOidcSecret} = {
      share = true;

      prompts.client-id = {
        description = "Keycloak Client ID for Garage UI";
        type = "line";
        persist = false;
      };

      prompts.client-secret = {
        description = "Keycloak Client Secret for Garage UI";
        type = "hidden";
        persist = false;
      };

      files.${garageUiOidcSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.jq];

      script = ''
        set -euo pipefail

        client_id="$(tr -d '\r\n' < "$prompts/client-id")"
        client_secret="$(tr -d '\r\n' < "$prompts/client-secret")"

        # Create the SopsSecret YAML using jq
        jq -n \
          --arg client_secret "$client_secret" \
          '{
            apiVersion: "isindir.github.com/v1alpha3",
            kind: "SopsSecret",
            metadata: {
              name: "garage-ui-oidc-secret",
              namespace: "garage"
            },
            spec: {
              secretTemplates: [{
                name: "garage-ui-oidc-secret",
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
          /dev/stdin > "$out/${garageUiOidcSecret}"
      '';
    };
  };
}
