{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  gitea-admin-secret = "forgejo-admin-secret";
  forgejo-keycloak-oauth-secret = "forgejo-keycloak-oauth-secret";
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
  };
}
