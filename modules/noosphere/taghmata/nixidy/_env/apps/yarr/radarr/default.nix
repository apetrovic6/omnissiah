{
  domain,
  namespace,
  db-cluster-name,
  ...
}: {
  imports = [
    ../../../../_modules/templates/database-template.nix
  ];

  applications.radarr = {
    resources.persistentVolumeClaims.radarr-pvc = {
      metadata = {
        inherit namespace;

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

    resources.deployments.radarr = {
      metadata = {
        inherit namespace;
        labels.app = "radarr";
      };

      spec = {
        selector = {
          matchLabels = {
            app = "radarr";
          };
        };
      };

      spec.template = {
        metadata.labels.app = "radarr";
        spec.volumes = [
          {
            name = "config";
            persistentVolumeClaim.claimName = "radarr-pvc";
          }

          {
            name = "data";
            nfs = {
              server = "192.168.1.61";
              path = "/volume1/data/";
            };
          }
        ];

        spec.containers = [
          {
            name = "radarr";

            image = "lscr.io/linuxserver/radarr:latest";
            volumeMounts = [
              {
                name = "config";
                mountPath = "/config";
              }

              {
                name = "data";
                mountPath = "/data";
              }
            ];

            env = [
              {
                name = "PUID";
                value = "1031";
              }
              {
                name = "PGID";
                value = "65537";
              }
              {
                name = "radarr__POSTGRES__HOST";
                value = "${db-cluster-name}-rw";
              }
              {
                name = "radarr__POSTGRES__PORT";
                value = "5432";
              }
              {
                name = "radarr__POSTGRES__USER";
                valueFrom.secretKeyRef = {
                  name = "pg-radarr-password";
                  key = "username";
                };
              }

              {
                name = "radarr__POSTGRES__PASSWORD";

                valueFrom.secretKeyRef = {
                  name = "pg-radarr-password";
                  key = "password";
                };
              }

              {
                name = "radarr__POSTGRES__MAINDB";
                value = "radarr";
              }

              {
                name = "radarr__POSTGRES__LOGDB";
                value = "radarr-logs";
              }
              {
                name = "radarr__SERVER__PORT";
                value = "8989";
              }
              # { name = "radarr__SERVER__URLBASE"; value = "";}
            ];

            ports = [{containerPort = 9696;}];
          }
        ];
      };
    };

    resources.services.radarr = {
      metadata = {
        inherit namespace;
      };

      spec = {
        type = "ClusterIP";
        selector = {app = "radarr";};

        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 8989;
          }
        ];
      };
    };

    resources.ingresses.radarr-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "radarr";
          "glance/icon" = "di:radarr";
          "glance/url" = "https://radarr.${domain}";
          "glance/description" = "Pvr";
          "glance/id" = "radarr";
          "glance/parent" = "radarr";
          "category" = "yarr";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "radarr-tls";
            hosts = ["radarr.${domain}"];
          }
        ];

        rules = [
          {
            host = "radarr.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "radarr";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    yamls = [
      (builtins.readFile ../../../../../../../../vars/shared/pg-radarr-sopssecret/pg-radarr-sopssecret/value)
    ];
  };
}
