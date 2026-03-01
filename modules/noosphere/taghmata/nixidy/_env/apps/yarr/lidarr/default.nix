{
  domain,
  namespace,
  db-cluster-name,
  ...
}: {
  imports = [
    ../../../../_modules/templates/database-template.nix
  ];

  applications.lidarr = {
    resources.persistentVolumeClaims.lidarr-pvc = {
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

    resources.deployments.lidarr = {
      metadata = {
        inherit namespace;
        labels.app = "lidarr";
      };

      spec = {
        selector = {
          matchLabels = {
            app = "lidarr";
          };
        };
      };

      spec.template = {
        metadata.labels.app = "lidarr";
        spec.volumes = [
          {
            name = "config";
            persistentVolumeClaim.claimName = "lidarr-pvc";
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
            name = "lidarr";

            image = "lscr.io/linuxserver/lidarr:latest";
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
                name = "lidarr__POSTGRES__HOST";
                value = "${db-cluster-name}-rw";
              }
              {
                name = "lidarr__POSTGRES__PORT";
                value = "5432";
              }
              {
                name = "lidarr__POSTGRES__USER";
                valueFrom.secretKeyRef = {
                  name = "pg-lidarr-password";
                  key = "username";
                };
              }

              {
                name = "lidarr__POSTGRES__PASSWORD";

                valueFrom.secretKeyRef = {
                  name = "pg-lidarr-password";
                  key = "password";
                };
              }

              {
                name = "lidarr__POSTGRES__MAINDB";
                value = "lidarr";
              }

              {
                name = "lidarr__POSTGRES__LOGDB";
                value = "lidarr-logs";
              }
              {
                name = "lidarr__SERVER__PORT";
                value = "7878";
              }
              # { name = "lidarr__SERVER__URLBASE"; value = "";}
            ];

            ports = [{containerPort = 7878;}];
          }
        ];
      };
    };

    resources.services.lidarr = {
      metadata = {
        inherit namespace;
      };

      spec = {
        type = "ClusterIP";
        selector = {app = "lidarr";};

        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 7878;
          }
        ];
      };
    };

    resources.ingresses.lidarr-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Lidarr";
          "glance/icon" = "di:lidarr";
          "glance/url" = "https://lidarr.${domain}";
          "glance/description" = "Music collection manager";
          "glance/id" = "lidarr";
          "glance/parent" = "lidarr";
          "category" = "yarr";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "lidarr-tls";
            hosts = ["lidarr.${domain}"];
          }
        ];

        rules = [
          {
            host = "lidarr.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "lidarr";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    yamls = [
      (builtins.readFile ../../../../../../../../vars/shared/pg-lidarr-sopssecret/pg-lidarr-sopssecret/value)
    ];
  };
}
