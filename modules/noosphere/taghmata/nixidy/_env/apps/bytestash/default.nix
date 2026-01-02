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

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/bytestash-jwt-secret/bytestash-jwt-secret/value)
      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: bytestash-tls
          namespace: ${namespace}
        spec:
          secretName: bytestash-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - bytestash.${domain}
      ''
    ];

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
          tls = [
            {
              secretName = "bytestash-tls";
              hosts = ["bytestash.${domain}"];
            }
          ];
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
