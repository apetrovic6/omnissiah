{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  bytestashJwtSecret = "bytestash-jwt-secret";
  bytestashOidcSecret = "bytestash-zitadel-client-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${bytestashJwtSecret} = {
      share = true;

      files.${bytestashJwtSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${bytestashJwtSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${bytestashJwtSecret}
          namespace: bytestash
        spec:
          secretTemplates:
            - name: ${bytestashJwtSecret}
              type: Opaque
              stringData:
                jwt-key: "$secret"
                expiry: "24h"
        EOF
      '';
    };

    clan.core.vars.generators.${bytestashOidcSecret} = {
      share = true;

      prompts.client-id = {
        description = "Client ID";
        type = "line";
        persist = false;
      };

      prompts.client-secret = {
        description = "Client Secret";
        type = "hidden";
        persist = false;
      };

      files.${bytestashOidcSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
               set -euo pipefail

               clientId="$(tr -d '\r\n' < "$prompts/client-id")"
               clientSecret="$(tr -d '\r\n' < "$prompts/client-secret")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${bytestashOidcSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${bytestashOidcSecret}
          namespace: bytestash
        spec:
          secretTemplates:
            - name: ${bytestashOidcSecret}
              type: Opaque
              stringData:
                "oidc.zitadel.clientId": "$clientId"
                "oidc.zitadel.clientSecret": "$clientSecret"
        EOF
      '';
    };
  };
}
