{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  meiliSearchSecret = "karakeep-meilisearch-secret";
  karakeepSecret = "karakeep-secret";
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

    clan.core.vars.generators.${karakeepSecret} = {
      share = true;

      files.${karakeepSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -base64 36)"
               nextpublicsecret="$(openssl rand -base64 36)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${karakeepSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${karakeepSecret}
          namespace: karakeep
        spec:
          secretTemplates:
            - name: ${karakeepSecret}
              type: Opaque
              stringData:
                NEXTAUTH_SECRET: "$secret"
                NEXT_PUBLIC?SECRET: "$nextpublicsecret"
        EOF
      '';
    };
  };
}
