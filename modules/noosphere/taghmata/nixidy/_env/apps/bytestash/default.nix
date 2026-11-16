{
  charts,
  config,
  vars,
  ingressAnnotations,
  ...
}: let
  namespace = "bytestash";
  domain = config.noosphere.domain;
in {
  applications.bytestash = {
    inherit namespace;
    createNamespace = true;

    sopsSecrets = ["bytestash-jwt-secret"];

    helm.releases.bytestash = {
      chart = charts.bytestash.bytestash;

      values = {
        persistence = {
          enabled = true;
          storageClassName = "longhorn";
          size = "5Gi";
        };

        bytestash = {
          baseUrl = "";
          existingJwtSecret = {
            secretName = "bytestash-jwt-secret";
            jwtKey = "jwt-key";
            expirityKey = "expiry";
          };
        };

        livenessProbe = {initialDelaySeconds = 120;};
        readinessProbe = {initialDelaySecodns = 120;};

        ingress = {
          enabled = true;
          className = "traefik";
          host = "bytestash.${domain}";
          path = "/";
          pathType = "Prefix";
          annotations = ingressAnnotations {
            glance = {
              name = "ByteStash";
              icon = "di:bytestash";
              url = "https://bytestash.${domain}";
              description = "Code Snipet Solution";
              id = "bytestash";
              parent = "bytestash";
              category = "utils";
            };
          };
          tls = [
            {
              secretName = "bytestash-tls";
              hosts = ["bytestash.${domain}"];
            }
          ];
        };

        # oidc = {
        #   enabled = false;
        #   name = "Zitadel";
        #   issuerUrl = "https://zitadel.${domain}";
        #   clientSecret = "bytestash-zitadel-client-secreta";
        #   scopes = "openid profile email groups";
        # };

        containerSecurityContext = {
          capabilities = {
            drop = ["ALL"];
          };
          readOnlyRootFilesystem = true;
          runAsNonRoot = true;
          runAsUser = 1000;
        };
        podSecurityContext = {
          fsGroup = 1000;
          runAsGroup = 1000;
          runAsNonRoot = true;
          runAsUser = 1000;
        };
      };
    };
  };
}
