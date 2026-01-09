{
  config,
  charts,
  ...
}: let
  domain = config.noosphere.domain;
  url = "crow.${domain}";
  namespace = "crow";
  db-cluster-name = "pg-crow";
  objectStoreName = "crow-object-store";
  barmanPluginName = "barman-cloud.cloudnative-pg.io";
  volumeSize = "2Gi";
in {
  imports = [../../../_modules/templates/garage-object-store.nix];

  applications.crow = {
    inherit namespace;
    createNamespace = true;

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };

    helm.releases.crowci = {
      chart = charts.crowci.crow;
      values = {
        server = {
          enabled = true;
          encryption.disable = true;
          createAgentSecret = true;
          env = {
            CROW_ADMIN = "crow,admin,manjo";
            CROW_HOST = "https://${url}";
            CROW_FORGEJO = true;
            CROW_DATABASE_DRIVER = "postgres";
            CROW_DATABASE_DATASOURCE = "postgres://\${username}:\${password}@${db-cluster-name}-rw:5432/app?sslmode=disable";
            CROW_BACKEND_K8S_VOLUME_SIZE = volumeSize;
            CROW_MAINTENANCE_KUBERNETES_CLEANUP_AGE = "168h";
            # CROW_CONFIG_SERVICE_ENDPOINT="http://config-service.crow.svc:8080";
          };

          extraSecretNamesForEnvFrom = [
            "${db-cluster-name}-app"
          ];

          ingress = {
            enabled = true;
            annotations = {
              "glance/name" = "Crow CI";
              "glance/icon" = "https://codeberg.org/repo-avatars/26541ad8113b12ff2f55a506416973d715de94518717de5e8c67faa59ccd13ba";
              "glance/url" = "https://${url}";
              "glance/description" = "CI/CD";
              "glance/id" = "crowci";
              "glance/parent" = "crowci";
              "category" = "utils";
            };
            tls = [
              {
                secretName = "crow-tls";
                hosts = [url];
              }
            ];
            hosts = [
              {
                ingressClassName = "traefik";
                host = "https://${url}";
                paths = [
                  {
                    backend = {
                      serviceName = "crow-server";
                      servicePort = 8080;
                    };
                  }
                ];
              }
            ];
          };
          metrics.enabled = true;

          replicaCount = 3;
          secrets = [];
        };

        agent = {
          storageClass = "longhorn-rec-delete-strict-local ";
          replicaCount = 3;
          extraSecretNamesForEnvFrom = [];
          env = {
            CROW_BACKEND_K8S_VOLUME_SIZE = volumeSize;
          };
        };

        grafana.dashboards.enabled = true;
        prometheus = {
          podMonitor.enabled = true;
          rules.enabled = true;
        };
      };
    };

    resources.scheduledBackups."${db-cluster-name}-scheduled-backup" = {
      metadata.namespace = namespace;
      spec = {
        schedule = "0 2 0 * * *"; # Backup at 2AM every night
        backupOwnerReference = "self";
        cluster.name = db-cluster-name;
        method = "plugin";
        pluginConfiguration.name = barmanPluginName;
        immediate = true;
      };
    };

    resources.backups."${db-cluster-name}-backup" = {
      metadata.namespace = namespace;
      spec = {
        cluster.name = "${db-cluster-name}";
        method = "plugin";
        pluginConfiguration.name = barmanPluginName;
      };
    };

    resources.clusters.${db-cluster-name} = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.proj.io/sync-hook" = "PreSync";
        };
      };

      spec = {
        primaryUpdateStrategy = "unsupervised";
        instances = 3;
        storage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "1Gi";
        };

        # bootstrap.recovery.source = "origin";

        # externalClusters = [
        #   {
        #     name = "origin";
        #     plugin = {
        #       name = "barman-cloud.cloudnative-pg.io";
        #       parameters = {
        #         barmanObjectName = objectStoreName;
        #         serverName = "pg-yarr";
        #       };
        #     };
        #   }
        # ];

        walStorage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "1Gi";
        };

        plugins = [
          {
            name = "barman-cloud.cloudnative-pg.io";
            isWALArchiver = true;
            parameters.barmanObjectName = objectStoreName;
          }
        ];

        postgresql.parameters = {
          shared_buffers = "1GB";
          max_connections = "200";
          log_statement = "ddl";
        };

        # managed = {
        #   roles = [
        #     {
        #       name = "seerr";
        #       ensure = "present";
        #       comment = "Seerr User";
        #       login = true;
        #       superuser = false;
        #       passwordSecret.name = "pg-seerr-password";
        #     }
        #   ];
        # };

        monitoring.enablePodMonitor = true;
      };
    };

    # resources.databases.db-crow = {
    #   metadata = {
    #     inherit namespace;
    #     annotations = {
    #       "argocd.proj.io/sync-options" = "Prune=false";
    #     };
    #   };
    #   spec = {
    #     name = "crow";
    #     owner = "app";
    #     cluster.name = "${db-cluster-name}";
    #   };
    # };
  };
}
