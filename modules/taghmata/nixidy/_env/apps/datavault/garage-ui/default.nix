# The web UI of one Garage cluster. Both clusters get one, from the same
# chart and in the garage-operator namespace:
#
#   (import ./apps/datavault/garage-ui { cluster = "main"; ... })
{
  # "main" or "backup".
  cluster,
  # Service of the cluster's S3 API.
  s3Service,
}: {
  charts,
  config,
  lib,
  ...
}: let
  name = "garage-${cluster}-ui";
  title = lib.toSentenceCase cluster;
  namespace = "garage-operator";
  domain = config.noosphere.domain;
  sso = config.noosphere.sso;
in {
  applications.${name} = {
    inherit namespace;

    sopsSecrets = ["${name}-jwt-token-secret"];

    ingresses.${name} = {
      inherit namespace;
      host = "ui.${cluster}.garage.${domain}";
      service = "${name}";
      port = 80;
      tlsSecret = "${name}-tls";
      glance = {
        name = "Garage ${title}";
        icon = "di:garage";
        description = "Distributed S3 Storage (${title})";
        id = "garage-${cluster}";
        category = "storage";
      };
    };

    resources.deployments.${name}.spec.template.spec.containers.garage-ui.env = {
      GARAGE_UI_AUTH_OIDC_CLIENT_ID.valueFrom.secretKeyRef = {
        name = "${name}-oidc-secret";
        key = "client-id";
      };
    };

    helm.releases.${name} = {
      chart = charts.noooste.garage-ui;

      values = {
        fullnameOverride = "${name}";

        config = {
          garage = {
            endpoint = "http://${s3Service}:3900";
            admin_endpoint = "http://garage-${cluster}-admin:3903";
            region = cluster;

            # The cluster's own admin token (taghmata/reliquary/garage-<cluster>).
            # It has to be under `garage`: that is the only place the chart reads
            # it. Anywhere else it is ignored without an error, and the chart
            # falls back to a Secret named <release>-admin-token.
            existingSecret = {
              name = "garage-${cluster}-admin-token";
              key = "admin-token";
            };
          };

          cors = {
            enabled = true;
            allowed_origins = ["https://ui.${cluster}.garage.${domain}"];
          };

          serviceMonitor = {
            enabled = true;
            interval = "30s";
            path = "/api/v1/monitoring/metrics";
            labels = {prometheus = "kube-prometheus";};
          };

          server = {
            domain = "ui.${cluster}.garage.${domain}";
            root_url = "https://ui.${cluster}.garage.${domain}";
            protocol = "http";
            host = "0.0.0.0";
            port = 8080;
            environment = "production";
          };

          auth = {
            jwt_private_key_secret = {
              name = "${name}-jwt-token-secret";
              key = "jwt-key.pem";
            };

            oidc = let
              provider = lib.toLower sso.provider;
            in {
              enabled = true;
              provider_name = sso.provider;
              issuer_url = "https://${provider}.${domain}";
              auth_url = "https://${provider}.${domain}/authorize";
              token_url = "https://${provider}.${domain}/api/oidc/token";
              userinfo_url = "https://${provider}.${domain}/api/oidc/userinfo";
              client_id = "${name}";
              existingSecret = {
                name = "${name}-oidc-secret";
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
              cookie_name = "garage_${cluster}_session";
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
