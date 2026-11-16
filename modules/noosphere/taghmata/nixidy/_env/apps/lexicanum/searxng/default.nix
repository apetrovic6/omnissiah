{config, ...}: let
  namespace = "searxng";
  domain = config.noosphere.domain;
  labels = {
    app = "searxng";
  };

  valkeyLabels = {
    app = "searxng-valkey";
  };
in {
  applications.searxng = {
    inherit namespace;
    createNamespace = true;

    resources.persistentVolumeClaims.searxng-pvc = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "longhorn-rec-1";
        resources.requests.storage = "1Gi";
      };
    };

    resources.persistentVolumeClaims.valkey-pvc = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "longhorn-rec-1";
        resources.requests.storage = "2Gi";
      };
    };

    resources.deployments.searxng = {
      metadata = {
        inherit namespace labels;
      };

      spec = {
        replicas = 1;
        selector.matchLabels = labels;

        template = {
          metadata = {inherit labels;};
          spec = {
            volumes = [
              {
                name = "searxng";
                persistentVolumeClaim.claimName = "searxng-pvc";
              }
            ];

            containers = [
              {
                name = "searxng";
                image = "docker.io/searxng/searxng:2026.1.24-eea189286";
                ports = [{containerPort = 8080;}];
                volumeMounts = [
                  {
                    name = "searxng";
                    mountPath = "/etc/searxng";
                  }

                  {
                    name = "searxng";
                    mountPath = "/var/cache/searxng";
                  }
                ];

                env = [
                  {
                    name = "SEARXNG_BASE_URL";
                    value = "https://searx.${domain}";
                  }
                ];
              }
            ];
          };
        };
      };
    };

    resources.services.searxng = {
      metadata = {
        inherit namespace;
      };
      spec = {
        type = "ClusterIP";
        selector = labels;
        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 8080;
          }
        ];
      };
    };

    resources.services.valkey = {
      metadata = {
        inherit namespace;
      };
      spec = {
        type = "ClusterIP";
        selector = valkeyLabels;
        ports = [
          {
            protocol = "TCP";
            port = 6379;
            targetPort = 6379;
          }
        ];
      };
    };

    resources.deployments.redis = {
      metadata = {
        inherit namespace;
        labels = valkeyLabels;
      };

      spec = {
        replicas = 1;
        selector.matchLabels = valkeyLabels;

        template = {
          metadata.labels = valkeyLabels;
          spec = {
            volumes = [
              {
                name = "valkey";
                persistentVolumeClaim.claimName = "valkey-pvc";
              }
            ];

            containers = [
              {
                name = "valkey";
                image = "docker.io/valkey/valkey:9-alpine";
                command = ["valkey-server"];
                ports = [{containerPort = 6379;}];
                args = [
                  "--save"
                  "30"
                  "1"
                ];
                volumeMounts = [
                  {
                    name = "valkey";
                    mountPath = "/data";
                  }
                ];
              }
            ];
          };
        };
      };
    };

    ingresses.searxng-ip-root = {
      inherit namespace;
      host = "searx.${domain}";
      service = "searxng";
      port = 80;
      tlsSecret = "searxng-tls";
      protect = true;
      glance = {
        name = "Searxng";
        icon = "di:searxng";
        description = "Private Meta Search Engine";
        id = "searxng";
        parent = "searxng";
        category = "search";
      };
    };
  };
}
