{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  harborAdminPassword = "harbor-admin-password-secret";
  harborS3Storage = "harbor-s3-secret-key";
  harborSecretSecretKey = "harbor-secret-secret-key";
  harborJobServiceSecret = "harbor-job-service-secret";
  harborRegistryHttpSecret = "harbor-registry-http-secret";
  harborRegistryCredentialsSecret = "harbor-registry-credentials-secret";
  harborRedisPasswordSecret = "harbor-redis-password-secret";
  harborPostgresSecret = "pg-harbor-postgres-secret";
  harborCoreSecret = "harbor-core-secret";
  harborTokenSvcTls = "harbor-core-svc-tls";
  harborOidcSecret = "harbor-oidc-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${harborAdminPassword} = {
      share = true;

      files.${harborAdminPassword}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 16)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${harborAdminPassword}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborAdminPassword}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborAdminPassword}
              type: Opaque
              stringData:
                HARBOR_ADMIN_PASSWORD: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${harborSecretSecretKey} = {
      share = true;

      files.${harborSecretSecretKey}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 8)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${harborSecretSecretKey}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborSecretSecretKey}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborSecretSecretKey}
              type: Opaque
              stringData:
                secretKey: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${harborJobServiceSecret} = {
      share = true;

      files.${harborJobServiceSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 8)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${harborJobServiceSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborJobServiceSecret}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborJobServiceSecret}
              type: Opaque
              stringData:
                JOBSERVICE_SECRET: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${harborRegistryHttpSecret} = {
      share = true;

      files.${harborRegistryHttpSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 8)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${harborRegistryHttpSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborRegistryHttpSecret}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborRegistryHttpSecret}
              type: Opaque
              stringData:
                REGISTRY_HTTP_SECRET: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${harborRegistryCredentialsSecret} = {
      share = true;
      files.${harborRegistryCredentialsSecret}.secret = false;

      # htpasswd comes from apache httpd utils
      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl pkgs.apacheHttpd];

      script = ''
            set -euo pipefail

            user="harbor"
            pwd="$(openssl rand -base64 32 | tr -d '\n' | head -c 32)"

            # Generates: user:$2y$...
            htpwd="$(htpasswd -nbB "$user" "$pwd")"

            sops encrypt\
              --age "${ageKey}" \
              --encrypted-suffix "Templates" \
              --input-type yaml --output-type yaml \
              /dev/stdin > "$out/${harborRegistryCredentialsSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborRegistryCredentialsSecret}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborRegistryCredentialsSecret}
              type: Opaque
              stringData:
                REGISTRY_PASSWD: "$pwd"
                REGISTRY_HTPASSWD: "$htpwd"
      '';
    };

    clan.core.vars.generators.${harborRedisPasswordSecret} = {
      share = true;

      files.${harborRedisPasswordSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 16)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${harborRedisPasswordSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborRedisPasswordSecret}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborRedisPasswordSecret}
              type: Opaque
              stringData:
                REDIS_PASSWORD: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${harborS3Storage} = {
      share = true;

      prompts.access-key-id = {
        description = "Enter Access Key ID: ";
        type = "line";
        persist = false;
      };

      prompts.access-key-secret = {
        description = "Enter Access Key Secret: ";
        type = "hidden";
        persist = false;
      };

      files.${harborS3Storage}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                access_key="$(tr -d '\r\n' < "$prompts/access-key-id")"
                secret_key="$(tr -d '\r\n' < "$prompts/access-key-secret")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${harborS3Storage}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborS3Storage}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborS3Storage}
              type: Opaque
              stringData:
                REGISTRY_STORAGE_S3_ACCESSKEY: "$access_key"
                REGISTRY_STORAGE_S3_SECRETKEY: "$secret_key"
        EOF
      '';
    };

    clan.core.vars.generators."${harborPostgresSecret}" = {
      share = true;

      prompts.pg-harbor-username = {
        description = "DB Username";
        type = "line";
        persist = false;
      };

      prompts.pg-harbor-password = {
        description = "DB Password";
        type = "hidden";
        persist = false;
      };

      files."${harborPostgresSecret}".secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                username="$(tr -d '\r\n' < "$prompts/pg-harbor-username")"
                password="$(tr -d '\r\n' < "$prompts/pg-harbor-password")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${harborPostgresSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${harborPostgresSecret}
          namespace: harbor
        spec:
          secretTemplates:
            - name: ${harborPostgresSecret}
              labels:
                cnpg.io/reload: "true"
              type: Opaque
              stringData:
                username: "$username"
                password: "$password"
        EOF
      '';
    };

    # clan.core.vars.generators.${harborTokenSvcTls} = {
    #   share = true;
    #   files.${harborTokenSvcTls}.secret = false;

    #   runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl pkgs.gnused];

    #   script = let
    #     NAMESPACE = "harbor";
    #   in ''
    #         set -euo pipefail

    #         tmp="$(mktemp -d)"
    #         trap 'rm -rf "$tmp"' EXIT

    #         # PKCS#1 key (Harbor token service is picky here)
    #        openssl genrsa -traditional -out "$tmp/tls.key" 4096

    #         openssl req -new -x509 -sha256 -days 3650 \
    #           -key "$tmp/tls.key" \
    #           -subj "/CN=harbor-token-service" \
    #           -out "$tmp/tls.crt"

    #         sops encrypt \
    #           --age "${ageKey}" \
    #           --encrypted-suffix "Templates" \
    #           --input-type yaml --output-type yaml \
    #           /dev/stdin > "$out/${harborTokenSvcTls}" <<EOF
    #     apiVersion: isindir.github.com/v1alpha3
    #     kind: SopsSecret
    #     metadata:
    #       name: ${harborTokenSvcTls}
    #       namespace: ${NAMESPACE}
    #     spec:
    #       secretTemplates:
    #         - name: ${harborTokenSvcTls}
    #           type: kubernetes.io/tls
    #           stringData:
    #             tls.crt: |-
    #     $(sed 's/^/          /' "$tmp/tls.crt")
    #             tls.key: |-
    #     $(sed 's/^/          /' "$tmp/tls.key")
    #     EOF
    #   '';
    # };

    clan.core.vars.generators.${harborCoreSecret} = {
      share = true;
      files.${harborCoreSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl pkgs.gnused];

      script = let
        NAMESPACE = "harbor";
      in
        /*
        bash
        */
        ''
              set -euo pipefail

              tmp="$(mktemp -d)"
              trap 'rm -rf "$tmp"' EXIT

              # 16 chars required
              core_secret="$(openssl rand -hex 8)"   # 16 hex chars

              # 32 chars required
              xsrf_key="$(openssl rand -hex 16)"     # 32 hex chars

              # Token service keypair (does NOT need to be Let's Encrypt)
              openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$tmp/tls.key"
              openssl req -new -x509 -sha256 -days 3650 \
                -key "$tmp/tls.key" \
                -subj "/CN=harbor-token-service" \
                -out "$tmp/tls.crt"

              sops encrypt \
                --age "${ageKey}" \
                --encrypted-suffix "Templates" \
                --input-type yaml --output-type yaml \
                /dev/stdin > "$out/${harborCoreSecret}" <<EOF
          apiVersion: isindir.github.com/v1alpha3
          kind: SopsSecret
          metadata:
            name: ${harborCoreSecret}
            namespace: ${NAMESPACE}
          spec:
            secretTemplates:
              - name: ${harborCoreSecret}
                type: Opaque
                stringData:
                  secret: "$core_secret"
                  CSRF_KEY: "$xsrf_key"
                  tls.crt: |-
          $(sed 's/^/          /' "$tmp/tls.crt")
                  tls.key: |-
          $(sed 's/^/          /' "$tmp/tls.key")
          EOF
        '';
    };

    clan.core.vars.generators.${harborOidcSecret} = {
      share = true;

      prompts.client-id = {
        description = "Pocket ID Client ID for Harbor (from tofunix harbor-oidc secret or Pocket ID UI)";
        type = "line";
        persist = false;
      };

      prompts.client-secret = {
        description = "Pocket ID Client Secret for Harbor (from tofunix harbor-oidc secret or Pocket ID UI)";
        type = "hidden";
        persist = false;
      };

      files.${harborOidcSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.jq];

      script = ''
        set -euo pipefail

        client_id="$(tr -d '\r\n' < "$prompts/client-id")"
        client_secret="$(tr -d '\r\n' < "$prompts/client-secret")"

        # Create Harbor CONFIG_OVERWRITE_JSON
        config_json=$(jq -cn \
          --arg auth_mode "oidc_auth" \
          --arg oidc_name "Pocket ID" \
          --arg oidc_endpoint "https://id.noosphere.uk" \
          --arg oidc_client_id "$client_id" \
          --arg oidc_client_secret "$client_secret" \
          --arg oidc_groups_claim "groups" \
          --arg oidc_admin_group "Admin" \
          --arg oidc_scope "openid,profile,email" \
          --argjson oidc_verify_cert true \
          --argjson oidc_auto_onboard true \
          --arg oidc_user_claim "preferred_username" \
          '{
            auth_mode: $auth_mode,
            oidc_name: $oidc_name,
            oidc_endpoint: $oidc_endpoint,
            oidc_client_id: $oidc_client_id,
            oidc_client_secret: $oidc_client_secret,
            oidc_groups_claim: $oidc_groups_claim,
            oidc_admin_group: $oidc_admin_group,
            oidc_scope: $oidc_scope,
            oidc_verify_cert: $oidc_verify_cert,
            oidc_auto_onboard: $oidc_auto_onboard,
            oidc_user_claim: $oidc_user_claim
          }'
        )

        # Create the SopsSecret YAML using jq to handle proper escaping
        jq -n \
          --arg config_json "$config_json" \
          '{
            apiVersion: "isindir.github.com/v1alpha3",
            kind: "SopsSecret",
            metadata: {
              name: "harbor-oidc-config",
              namespace: "harbor"
            },
            spec: {
              secretTemplates: [{
                name: "harbor-oidc-config",
                type: "Opaque",
                stringData: {
                  CONFIG_OVERWRITE_JSON: $config_json
                }
              }]
            }
          }' | sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type json --output-type yaml \
          /dev/stdin > "$out/${harborOidcSecret}"
      '';
    };
  };
}
