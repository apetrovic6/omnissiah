{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  woodpeckerAgentSecret = "woodpecker-default-agent-secret";
  forgejoWoodpeckerOauth = "woodpecker-forgejo-oauth-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${woodpeckerAgentSecret} = {
      share = true;

      files.${woodpeckerAgentSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${woodpeckerAgentSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${woodpeckerAgentSecret}
          namespace: woodpecker
        spec:
          secretTemplates:
            - name: ${woodpeckerAgentSecret}
              type: Opaque
              stringData:
                WOODPECKER_DEFAULT_AGENT_SECRET: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${forgejoWoodpeckerOauth} = {
      share = true;

      prompts.client-id= {
        description = "Enter Client ID: ";
        type = "line";
        persist = false;
      };

      prompts.client-secret= {
        description = "Enter Client Secret: ";
        type = "hidden";
        persist = false;
      };

      files.${forgejoWoodpeckerOauth}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                client_id="$(tr -d '\r\n' < "$prompts/client-id")"
                client_secret="$(tr -d '\r\n' < "$prompts/client-secret")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${forgejoWoodpeckerOauth}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${forgejoWoodpeckerOauth}
          namespace: woodpecker
        spec:
          secretTemplates:
            - name: ${forgejoWoodpeckerOauth}
              type: Opaque
              stringData:
                WOODPECKER_CLIENT_ID: "$client_id"
                WOODPECKER_CLIENT_SECRET: "$client_secret"
        EOF
      '';
    };  };
}
