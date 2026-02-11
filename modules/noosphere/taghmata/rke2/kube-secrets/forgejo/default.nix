{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  gitea-admin-secret = "forgejo-admin-secret";
  forgejo-keycloak-oauth-secret = "forgejo-keycloak-oauth-secret";
  forgejo-s3-secret-key = "forgejo-s3-secret-key";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${gitea-admin-secret} = {
      share = true;

      prompts.username = {
        description = "Enter Forgejo Admin Username: ";
        type = "line";
        persist = false;
      };

      prompts.password = {
        description = "Enter Forgejo Admin Password: ";
        type = "hidden";
        persist = false;
      };

      files.${gitea-admin-secret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                username="$(tr -d '\r\n' < "$prompts/username")"
                password="$(tr -d '\r\n' < "$prompts/password")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${gitea-admin-secret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${gitea-admin-secret}
          namespace: forgejo
        spec:
          secretTemplates:
            - name: ${gitea-admin-secret}
              type: Opaque
              stringData:
                username: "$username"
                password: "$password"
        EOF
      '';
    };

    clan.core.vars.generators.${forgejo-keycloak-oauth-secret} = {
      share = true;

      prompts.key = {
        description = "Enter Access Key ID: ";
        type = "line";
        persist = false;
      };

      prompts.secret = {
        description = "Enter Access Key Secret: ";
        type = "hidden";
        persist = false;
      };

      files.${forgejo-keycloak-oauth-secret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                key="$(tr -d '\r\n' < "$prompts/key")"
                secret="$(tr -d '\r\n' < "$prompts/secret")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${forgejo-keycloak-oauth-secret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${forgejo-keycloak-oauth-secret}
          namespace: forgejo
        spec:
          secretTemplates:
            - name: ${forgejo-keycloak-oauth-secret}
              type: Opaque
              stringData:
                key: "$key"
                secret: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${forgejo-s3-secret-key} = {
      share = true;

      prompts.access-key-id = {
        description = "S3 access key ID for the forgejo Garage bucket";
        type = "line";
        persist = false;
      };

      prompts.access-key-secret = {
        description = "S3 secret access key for the forgejo Garage bucket";
        type = "hidden";
        persist = false;
      };

      files.${forgejo-s3-secret-key}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                access_key="$(tr -d '\r\n' < "$prompts/access-key-id")"
                secret_key="$(tr -d '\r\n' < "$prompts/access-key-secret")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${forgejo-s3-secret-key}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${forgejo-s3-secret-key}
          namespace: forgejo
        spec:
          secretTemplates:
            - name: ${forgejo-s3-secret-key}
              type: Opaque
              stringData:
                MINIO_ACCESS_KEY_ID: "$access_key"
                MINIO_SECRET_ACCESS_KEY: "$secret_key"
        EOF
      '';
    };
  };
}
