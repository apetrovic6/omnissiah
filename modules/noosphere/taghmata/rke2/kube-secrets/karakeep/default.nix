{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  meiliSearchSecret= "karakeep-meilisearch-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${meiliSearchSecret} = {
      share = true;

      files.${meiliSearchSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -base64 36)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${meiliSearchSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${meiliSearchSecret}
          namespace: karakeep
        spec:
          secretTemplates:
            - name: ${meiliSearchSecret}
              type: Opaque
              stringData:
                MEILI_MASTER_KEY: "$secret"
        EOF
      '';
    };

    # clan.core.vars.generators.${fileNameAdmin} = {
    #   share = true;

    #   prompts.admin-token = {
    #     description = "Enter Garage admin token: ";
    #     type = "hidden";
    #     persist = false;
    #   };

    #   files.${fileNameAdmin}.secret = false;

    #   runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

    #   script = ''
    #            set -euo pipefail

    #             secret="$(tr -d '\r\n' < "$prompts/admin-token")"

    #     sops encrypt \
    #       --age "${ageKey}" \
    #       --encrypted-suffix "Templates" \
    #       --input-type yaml --output-type yaml \
    #       /dev/stdin > "$out/${fileNameAdmin}" <<EOF
    #     apiVersion: isindir.github.com/v1alpha3
    #     kind: SopsSecret
    #     metadata:
    #       name: ${fileNameAdmin}
    #       namespace: garage
    #     spec:
    #       secretTemplates:
    #         - name: ${fileNameAdmin}
    #           type: Opaque
    #           stringData:
    #             admin-token: "$secret"
    #     EOF
    #   '';
    # };
  };
}
