{
  charts,
  config,
  lib,
  ...
}: let
  namespace = "garage-operator";
  domain = config.noosphere.domain;
  sso = config.noosphere.sso;
in {
  applications.garage-main-ui = {
    inherit namespace;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-main-admin-token/garage-main-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-main-ui-jwt-token-secret/garage-main-ui-jwt-token-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-main-ui-oidc-secret/garage-main-ui-oidc-secret/value)
    ];

    resources.ingresses.garage-main-ui = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Garage Main";
          "glance/icon" = "di:garage";
          "glance/url" = "https://ui.main.garage.${domain}";
          "glance/description" = "Distributed S3 Storage (Main)";
          "glance/id" = "garage-main";
          "glance/parent" = "garage";
          "category" = "storage";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "garage-main-ui-tls";
            hosts = ["ui.main.garage.${domain}"];
          }
        ];

        rules = [
          {
            host = "ui.main.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-main-ui";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    helm.releases.garage-main-ui = {
      chart = charts.noooste.garage-ui;

      values = {
        config = {
          garage = {
            endpoint = "http://garage-s3-api:3900";
            admin_endpoint = "http://garage-main-admin:3903";
            region = "main";
          };

          existingSecret = {
            name = "garage-main-admin-token";
            key = "admin-token";
          };

          cors = {
            enabled = true;
            allowed_origins = ["https://ui.main.garage.${domain}"];
          };

          serviceMonitor = {
            enabled = true;
            interval = "30s";
            path = "/api/v1/monitoring/metrics";
            labels = {prometheus = "kube-prometheus";};
          };

          server = {
            domain = "ui.main.garage.${domain}";
            root_url = "https://ui.main.garage.${domain}";
            protocol = "http";
            host = "0.0.0.0";
            port = 8080;
            environment = "production";
          };

          auth = {
            jwt_private_key_secret = {
              name = "garage-main-ui-jwt-token-secret";
              key = "jwt-key.pem";
            };

            oidc = let
              provider = lib.toLower sso.provider;
            in {
              enabled = true;
              provider_name = sso.provider;
              issuer_url = "https://${provider}.${domain}/realms/adeptus-terra";
              auth_url = "https://${provider}.${domain}/realms/adeptus-terra/protocol/openid-connect/auth";
              token_url = "https://${provider}.${domain}/realms/adeptus-terra/protocol/openid-connect/token";
              userinfo_url = "https://${provider}.${domain}/realms/adeptus-terra/protocol/openid-connect/userinfo";
              client_id = "garage-main-ui";
              existingSecret = {
                name = "garage-main-ui-oidc-secret";
                key = "client-secret";
              };
              scopes = ["openid" "email" "profile"];
              username_attribute = "preferred_username";
              email_attribute = "email";
              name_attribute = "name";
              admin_role = "admin";
              role_attribute_path = "resource_access.garage-main-ui.roles";
              cookie_secure = true;
              cookie_http_only = true;
              cookie_same_site = "lax";
              cookie_name = "garage_main_session";
              session_max_age = 86400;
              tls_skip_verify = false;
              skip_issuer_check = false;
              skip_expiry_check = false;
            };
          };
        };
      };
    };
  };
}
