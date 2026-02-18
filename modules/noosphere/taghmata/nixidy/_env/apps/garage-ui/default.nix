{
  charts,
  config,
  lib,
  ...
}: let
  namespace = "garage";
  domain = config.noosphere.domain;
  sso = config.noosphere.sso;
in {
  applications.garage-ui = {
    inherit namespace;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-ui-admin-token/garage-ui-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-ui-jwt-token-secret/garage-ui-jwt-token-secret/value)
    ];

    resources.ingresses.garage-ui-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Garage";
          "glance/icon" = "di:garage";
          "glance/url" = "https://ui.garage.${domain}";
          "glance/description" = "Distributed S3 Storage";
          "glance/id" = "garage";
          "glance/parent" = "garage";
          "category" = "storage";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "garage-ui-tls";
            hosts = ["ui.garage.${domain}"];
          }
        ];

        rules = [
          {
            host = "ui.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-ui";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    resources.deployments.garage-ui.spec.template.spec.containers.garage-ui.env = {
      GARAGE_UI_AUTH_OIDC_CLIENT_ID.valueFrom.secretKeyRef = {
        name = "garage-ui-oidc-secret";
        key = "client-id";
      };
    };

    helm.releases.garage-ui = {
      chart = charts.noooste.garage-ui;

      values = {
        config = {
          garage = {
            endpoint = "http://garage:3900";
            admin_endpoint = "http://garage-admin:3903";
            region = "garage";
          };

          existingSecret = {
            name = "garage-ui-admin-token";
            key = "admin-token";
          };

          cors = {
            enabled = true;
            allowed_origins = ["https://ui.garage.${domain}"];
          };

          serviceMonitor = {
            enabled = true;
            interval = "30s";
            path = "/api/v1/monitoring/metrics";
            labels = {prometheus = "kube-prometheus";};
          };

          server = {
            domain = "ui.garage.${domain}";
            root_url = "https://ui.garage.${domain}";
            protocol = "http";
            host = "0.0.0.0";
            port = 8080;
            environment = "production";
          };

          auth = {
            jwt_private_key_secret = {
              name = "garage-ui-jwt-token-secret";
              key = "jwt-key.pem";
            };

            oidc = let
              provider = lib.toLower sso.provider;
            in {
              enabled = true;
              provider_name = lib.toLower sso.provider;
              issuer_url = "https://${provider}.${domain}";
              auth_url = "https://${provider}.${domain}/authorize";
              token_url = "https://${provider}.${domain}/api/oidc/token";
              userinfo_url = "https://${provider}.${domain}/api/oidc/userinfo";
              # client_id = "garage-ui";
              existingSecret = {
                name = "garage-ui-oidc-secret";
                key = "client-secret";
              };
              scopes = ["openid" "email" "profile" "groups"];
              username_attribute = "preferred_username";
              email_attribute = "email";
              name_attribute = "name";
              admin_role = "Admin";
              role_attribute_path = "groups";
              cookie_secure = true;
              cookie_http_only = true;
              cookie_same_site = "lax";
              cookie_name = "garage_session";
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
