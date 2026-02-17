{
  domain,
  namespace,
  db-cluster-name,
  ...
}: {
  imports = [
    ../../../../_modules/templates/garage-object-store.nix
    ../../../../_modules/templates/database-template.nix
  ];

  applications.prowlarr = {
    resources.persistentVolumeClaims.prowlarr-pvc = {
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

    resources.deployments.prowlarr = {
      metadata = {
        inherit namespace;
        labels.app = "prowlarr";
      };

      spec = {
        selector = {
          matchLabels = {
            app = "prowlarr";
          };
        };
      };

      spec.template = {
        metadata.labels.app = "prowlarr";
        spec.volumes = [
          {
            name = "config";
            persistentVolumeClaim.claimName = "prowlarr-pvc";
          }
        ];

        spec.containers = [
          {
            name = "prowlarr";

            image = "lscr.io/linuxserver/prowlarr:latest";
            volumeMounts = [
              {
                name = "config";
                mountPath = "/config";
              }
            ];

            env = [
              {
                name = "PROWLARR__POSTGRES__HOST";
                value = "${db-cluster-name}-rw";
              }
              {
                name = "PROWLARR__POSTGRES__PORT";
                value = "5432";
              }
              {
                name = "PROWLARR__POSTGRES__USER";
                valueFrom.secretKeyRef = {
                  name = "pg-prowlarr-password";
                  key = "username";
                };
              }

              {
                name = "PROWLARR__POSTGRES__PASSWORD";

                valueFrom.secretKeyRef = {
                  name = "pg-prowlarr-password";
                  key = "password";
                };
              }

              {
                name = "PROWLARR__POSTGRES__MAINDB";
                value = "prowlarr";
              }

              {
                name = "PROWLARR__POSTGRES__LOGDB";
                value = "prowlarr-logs";
              }
              {
                name = "PROWLARR__SERVER__PORT";
                value = "9696";
              }
              # { name = "PROWLARR__SERVER__URLBASE"; value = "";}
            ];

            ports = [{containerPort = 9696;}];
          }
        ];
      };
    };

    resources.services.prowlarr = {
      metadata = {
        inherit namespace;
      };

      spec = {
        type = "ClusterIP";
        selector = {app = "prowlarr";};

        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 9696;
          }
        ];
      };
    };

    resources.ingresses.prowlarr-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Seerr";
          "glance/icon" = "di:prowlarr";
          "glance/url" = "https://prowlarr.${domain}";
          "glance/description" = "Media Management";
          "glance/id" = "prowlarr";
          "glance/parent" = "prowlarr";
          "category" = "yarr";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "prowlarr-tls";
            hosts = ["prowlarr.${domain}"];
          }
        ];

        rules = [
          {
            host = "prowlarr.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "prowlarr";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    yamls = [
      (builtins.readFile ../../../../../../../../vars/shared/pg-prowlarr-sopssecret/pg-prowlarr-sopssecret/value)
    ];
  };
}
