{
  config,
  charts,
  ...
}: let
  name = "woodpecker";
  domain = config.noosphere.domain;
  url = "${name}.${domain}";
  namespace = "${name}";
  db-cluster-name = "pg-${name}";
  objectStoreName = "${name}-object-store";
  barmanPluginName = "barman-cloud.cloudnative-pg.io";
  volumeSize = "2Gi";
in {
  imports = [../../../_modules/templates/garage-object-store.nix];

  applications.${name} = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/woodpecker-agent-secret/woodpecker-agent-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/woodpecker-forgejo-oauth-secret/woodpecker-forgejo-oauth-secret/value)
    ];

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };

    helm.releases.${name} = {
      chart = charts.woodpecker-ci.woodpecker;
      values = {
        server = {
          createAgentSecret = false;

          persistentVolume.storageClass = "longhorn";

          env = {
            WOODPECKER_ADMIN = "woodpecker,admin,manjo";
            WOODPECKER_HOST = "https://${url}";
            WOODPECKER_DATABASE_DRIVER = "postgres";
            WOODPECKER_DATABASE_DATASOURCE = "$(uri)";
            WOODPECKER_AGENT_SECRET = "$(agentSecret)";

            WOODPECKER_FORGEJO = "true";
            WOODPECKER_FORGEJO_URL = "https://forge.manjaca.xyz";
            WOODPECKER_FORGEJO_CLIENT = "$(CLIENT_ID)";
            WOODPECKER_FORGEJO_SECRET = "$(CLIENT_SECRET)";
          };

          extraSecretNamesForEnvFrom = [
            "${db-cluster-name}-app"
            "woodpecker-agent-secret"
            "woodpecker-forgejo-oauth-secret"
          ];

          ingress = {
            enabled = true;
            annotations = {
              "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
              "glance/name" = "Woodpecker CI";
              "glance/icon" = "di:woodpecker-ci";
              "glance/url" = "https://${url}";
              "glance/description" = "CI/CD";
              "glance/id" = name;
              "glance/parent" = name;
              "category" = "utils";
            };
            tls = [
              {
                secretName = "${name}-tls";
                hosts = [url];
              }
            ];
            hosts = [
              {
                ingressClassName = "traefik";
                host = url;
                paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                    backend = {
                      serviceName = "woodpecker-server";
                      servicePort = 8000;
                    };
                  }
                ];
              }
            ];
          };
        };

        agent = {
          persistence.storageClass = "longhorn-rec-delete-strict-local";
          replicaCount = 3;

          extraSecretNamesForEnvFrom = [
            "${db-cluster-name}-app"
            "woodpecker-agent-secret"
          ];

          env = {
            WOODPECKER_BACKEND_K8S_STORAGE_CLASS = "longhorn-rec-delete-strict-local";
            WOODPECKER_SERVER = "woodpecker-server:9000";
            WOODPECKER_AGENT_SECRET = "$(agentSecret)";
          };
        };

        metrics = {
          enabled = true;
          port = 9001;
        };

        prometheus = {
          podmonitor = {
            enabled = true;
            interval = "60s";
            labels = {};
          };
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
