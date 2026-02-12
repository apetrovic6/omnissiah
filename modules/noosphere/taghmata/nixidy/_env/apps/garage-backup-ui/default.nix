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
  applications.garage-backup-ui = {
    inherit namespace;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-ui-admin-token/garage-backup-ui-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-ui-jwt-token-secret/garage-backup-ui-jwt-token-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-ui-oidc-secret/garage-backup-ui-oidc-secret/value)
    ];

    resources.ingresses.garage-backup-ui = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Garage Backup";
          "glance/icon" = "di:garage";
          "glance/url" = "https://ui.backup.garage.${domain}";
          "glance/description" = "Distributed S3 Storage (Backup)";
          "glance/id" = "garage-backup";
          "glance/parent" = "garage";
          "category" = "storage";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "garage-backup-ui-tls";
            hosts = ["ui.backup.garage.${domain}"];
          }
        ];

        rules = [
          {
            host = "ui.backup.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-backup-ui";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    helm.releases.garage-backup-ui = {
      chart = charts.noooste.garage-ui;

      values = {
        fullnameOverride = "garage-backup-ui";

        config = {
          garage = {
            endpoint = "http://garage-backup-s3-api:3900";
            admin_endpoint = "http://garage-backup-admin:3903";
            region = "backup";
          };

          existingSecret = {
            name = "garage-backup-admin-token";
            key = "admin-token";
          };

          cors = {
            enabled = true;
            allowed_origins = ["https://ui.backup.garage.${domain}"];
          };

          serviceMonitor = {
            enabled = true;
            interval = "30s";
            path = "/api/v1/monitoring/metrics";
            labels = {prometheus = "kube-prometheus";};
          };

          server = {
            domain = "ui.backup.garage.${domain}";
            root_url = "https://ui.backup.garage.${domain}";
            protocol = "http";
            host = "0.0.0.0";
            port = 8080;
            environment = "production";
          };

          auth = {
            jwt_private_key_secret = {
              name = "garage-backup-ui-jwt-token-secret";
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
              client_id = "garage-backup-ui";
              existingSecret = {
                name = "garage-backup-ui-oidc-secret";
                key = "client-secret";
              };
              scopes = ["openid" "email" "profile"];
              username_attribute = "preferred_username";
              email_attribute = "email";
              name_attribute = "name";
              admin_role = "admin";
              role_attribute_path = "resource_access.garage-backup-ui.roles";
              cookie_secure = true;
              cookie_http_only = true;
              cookie_same_site = "lax";
              cookie_name = "garage_backup_session";
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
