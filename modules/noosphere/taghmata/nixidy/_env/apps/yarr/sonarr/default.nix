{
  domain,
  namespace,
  db-cluster-name,
  ...
}: {
  imports = [
    ../../../../_modules/templates/database-template.nix
  ];

  applications.sonarr = {
    resources.persistentVolumeClaims.sonarr-pvc = {
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

    resources.deployments.sonarr = {
      metadata = {
        inherit namespace;
        labels.app = "sonarr";
      };

      spec = {
        selector = {
          matchLabels = {
            app = "sonarr";
          };
        };
      };

      spec.template = {
        metadata.labels.app = "sonarr";
        spec.volumes = [
          {
            name = "config";
            persistentVolumeClaim.claimName = "sonarr-pvc";
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
            name = "sonarr";

            image = "lscr.io/linuxserver/sonarr:latest";
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
                name = "SONARR__POSTGRES__HOST";
                value = "${db-cluster-name}-rw";
              }
              {
                name = "SONARR__POSTGRES__PORT";
                value = "5432";
              }
              {
                name = "SONARR__POSTGRES__USER";
                valueFrom.secretKeyRef = {
                  name = "pg-sonarr-password";
                  key = "username";
                };
              }

              {
                name = "SONARR__POSTGRES__PASSWORD";

                valueFrom.secretKeyRef = {
                  name = "pg-sonarr-password";
                  key = "password";
                };
              }

              {
                name = "SONARR__POSTGRES__MAINDB";
                value = "sonarr";
              }

              {
                name = "SONARR__POSTGRES__LOGDB";
                value = "sonarr-logs";
              }
              {
                name = "SONARR__SERVER__PORT";
                value = "8989";
              }
              # { name = "SONARR__SERVER__URLBASE"; value = "";}
            ];

            ports = [{containerPort = 9696;}];
          }
        ];
      };
    };

    resources.services.sonarr = {
      metadata = {
        inherit namespace;
      };

      spec = {
        type = "ClusterIP";
        selector = {app = "sonarr";};

        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 8989;
          }
        ];
      };
    };

    resources.ingresses.sonarr-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Sonarr";
          "glance/icon" = "di:sonarr";
          "glance/url" = "https://sonarr.${domain}";
          "glance/description" = "Pvr";
          "glance/id" = "sonarr";
          "glance/parent" = "sonarr";
          "category" = "yarr";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "sonarr-tls";
            hosts = ["sonarr.${domain}"];
          }
        ];

        rules = [
          {
            host = "sonarr.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "sonarr";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    yamls = [
      (builtins.readFile ../../../../../../../../vars/shared/pg-sonarr-sopssecret/pg-sonarr-sopssecret/value)
    ];
  };
}
