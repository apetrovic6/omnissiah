{
  charts,
  config,
  ...
}: let
  namespace = "bytestash";
  domain = config.noosphere.domain;
in {
  applications.bytestash = {
    inherit namespace;
    createNamespace = true;

    helm.releases.bytestash = {
      chart = charts.bytestash.bytestash;

      values = {
        persistence = {
          enabled = true;
          storageClassName = "longhorn";
          size = "5Gi";
        };

        bytestash = {
          baseUrl = "bytestash.${domain}";
          existingJwtSecret = {
            secretName = "bytestash-jwt-secret";
            jwtKey = "jwt-key";
            expirityKey = "expirity-key";
          };
        };

        ingress = {
          enabled = true;
          className = "traefik";
          host = "bytestash.${domain}";
          path = "/";
          pathType = "Prefix";
          tls = ["bytestash-tls"];
        };
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
