{
  yarr,
  config,
  ...
}: let
  domain = config.noosphere.domain;
in {
  applications.seerr = {
    resources.persistentVolumeClaims.seerr-pvc = {
      metadata = {
        inherit (yarr) namespace;
        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };
      spec = {
        accessModes = ["ReadWriteMany"];
        storageClassName = "longhorn";
        resources.requests.storage = "2Gi";
      };
    };

    resources.deployments.seerr = {
      metadata = {
        name = "seerr-deployment";
        inherit (yarr) namespace;
        labels = {
          app = "seerr";
        };
      };

      spec = {
        replicas = 1;
        selector = {
          matchLabels = {
            app = "seerr";
          };
        };
        template = {
          metadata.labels.app = "seerr";
          spec.volumes = [
            {
              name = "config";
              persistentVolumeClaim.claimName = "seerr-pvc";
            }
          ];
          spec.containers = [
            {
              name = "seerr";
              image = "seerr/seerr:v3.4.1";
              volumeMounts = [
                {
                  name = "config";
                  mountPath = "/app/config";
                }
              ];

              env = [
                {
                  name = "DB_TYPE";
                  value = "postgres";
                }

                {
                  name = "DB_HOST";
                  value = "${yarr.dbClusterName}-rw";
                }

                {
                  name = "DB_PORT";
                  value = "5432";
                }

                {
                  name = "DB_USER";
                  valueFrom.secretKeyRef = {
                    name = "pg-seerr-password";
                    key = "username";
                  };
                }

                {
                  name = "DB_PASS";
                  valueFrom.secretKeyRef = {
                    name = "pg-seerr-password";
                    key = "password";
                  };
                }

                {
                  name = "DB_NAME";
                  value = "seerr";
                }
              ];
              ports = [
                {
                  containerPort = 5055;
                }
              ];
            }
          ];
        };
      };
    };

    resources.services.seerr = {
      metadata = {
        inherit (yarr) namespace;
      };
      spec = {
        type = "ClusterIP";
        selector = {
          app = "seerr";
        };
        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 5055;
          }
        ];
      };
    };

    resources.ingresses.seerr-ip-root = {
      metadata = {
        inherit (yarr) namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Seerr";
          "glance/icon" = "di:jellyseerr";
          "glance/url" = "https://seerr.${domain}";
          "glance/description" = "Media Management";
          "glance/id" = "seerr";
          "glance/parent" = "seerr";
          "category" = "yarr";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "seerr-tls";
            hosts = ["seerr.${domain}"];
          }
        ];

        rules = [
          {
            host = "seerr.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "seerr";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    sopsSecrets = ["pg-seerr-sopssecret"];
  };
}
