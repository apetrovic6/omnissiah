{config, ...}: let
  namespace = "yarr";
  domain = config.noosphere.domain;
  db-cluster-name = "pg-yarr-1";
  objectStoreName = "yarr-object-store";

  prowlarr = import ../prowlarr {inherit domain namespace db-cluster-name;};
  sonarr = import ../sonarr {inherit domain namespace db-cluster-name;};
in {
  imports = [
    ../../../../_modules/templates/garage-object-store.nix
    ../../../../_modules/templates/database-template.nix
    prowlarr
    sonarr
  ];

  applications.seerr = {
    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };

    resources.namespaces.yarr = {
      metadata = {
        name = namespace;
        labels.name = namespace;
      };
    };

    resources.persistentVolumeClaims.seerr-pvc = {
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

    resources.deployments.seerr = {
      metadata = {
        name = "seerr-deployment";
        inherit namespace;
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
              image = "seerr/seerr:preview-music-support";
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
                  value = "${db-cluster-name}-rw";
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
        inherit namespace;
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
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
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

    yamls = [
      (builtins.readFile ../../../../../../../../vars/shared/pg-seerr-sopssecret/pg-seerr-sopssecret/value)
    ];

    templates.cnpg-database-cluster.yarr-1 = {
      inherit namespace;
      overrideObjectStore = objectStoreName;
      cluster = {
        spec = {
          plugins = [
            {
              isWALArchiver = true;
              parameters.barmanObjectName = objectStoreName;
            }
          ];

          bootstrap.recovery.source = "origin";

          managed.roles = [
            {
              name = "seerr";
              ensure = "present";
              comment = "Seerr User";
              login = true;
              superuser = false;
              passwordSecret.name = "pg-seerr-password";
            }

            {
              name = "prowlarr";
              ensure = "present";
              comment = "Prowlarr User";
              login = true;
              superuser = false;
              passwordSecret.name = "pg-prowlarr-password";
            }
            {
              name = "sonarr";
              ensure = "present";
              comment = "Sonarr User";
              login = true;
              superuser = false;
              passwordSecret.name = "pg-sonarr-password";
            }
          ];

          externalClusters = [
            {
              plugin = {
                parameters = {
                  barmanObjectName = objectStoreName;
                  serverName = "pg-yarr-restored";
                };
              };
            }
          ];
        };
      };

      databases = [
        {
          name = "db-seerr";

          metadata = {
            annotations = {
              "argocd.proj.io/sync-options" = "Prune=false";
            };
          };
          spec = {
            name = "seerr";
            owner = "seerr";
            cluster.name = "${db-cluster-name}";
          };
        }

        {
          name = "db-prowlarr";

          metadata = {
            annotations = {
              "argocd.proj.io/sync-options" = "Prune=false";
            };
          };
          spec = {
            name = "prowlarr";
            owner = "prowlarr";
            cluster.name = "${db-cluster-name}";
          };
        }

        {
          name = "db-prowlarr-logs";

          metadata = {
            annotations = {
              "argocd.proj.io/sync-options" = "Prune=false";
            };
          };
          spec = {
            name = "prowlarr-logs";
            owner = "prowlarr";
            cluster.name = "${db-cluster-name}";
          };
        }

        {
          name = "db-sonarr";

          metadata = {
            annotations = {
              "argocd.proj.io/sync-options" = "Prune=false";
            };
          };
          spec = {
            name = "sonarr";
            owner = "sonarr";
            cluster.name = "${db-cluster-name}";
          };
        }

        {
          name = "db-sonarr-logs";

          metadata = {
            annotations = {
              "argocd.proj.io/sync-options" = "Prune=false";
            };
          };
          spec = {
            name = "sonarr-logs";
            owner = "sonarr";
            cluster.name = "${db-cluster-name}";
          };
        }
      ];

      backups = {
        scheduledBackups = [
          {
            metadata.namespace = namespace;
            spec = {
              schedule = "0 2 0 * * *"; # Backup at 2AM every night
              backupOwnerReference = "self";
              immediate = true;
            };
          }
        ];

        onDemandBackups = [
          {
            spec = {};
          }
        ];
      };
    };
  };
}
