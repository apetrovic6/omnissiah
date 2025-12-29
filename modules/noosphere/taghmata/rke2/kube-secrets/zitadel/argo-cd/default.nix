{...}: let
  ageKey = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
  fileName = "zitadel-argocd-secret";
 in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileName}= {
      share = true;

      prompts.client-id= {
        description = "Client ID";
        type = "line";
        persist = false;
      };

      prompts.client-secret= {
        description = "Client Secret";
        type = "hidden";
        persist = false;
      };

      files.${fileName}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
       set -euo pipefail

       clientId="$(tr -d '\r\n' < "$prompts/client-id")"
       clientSecret="$(tr -d '\r\n' < "$prompts/client-secret")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileName}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileName}
          namespace: yarr
        spec:
          secretTemplates:
            - name: ${fileName}
              labels:
                cnpg.io/reload: "true"
              type: Opaque
              stringData:
                oidc.zitadel.clientId: "$clientId"
                oidc.zitadel.clientSecret: "$clientSecret"
        EOF
      '';
    };
  };
}
