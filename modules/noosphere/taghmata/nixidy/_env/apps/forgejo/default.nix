{
  config,
  charts,
  ...
}: let
  name = "forgejo";
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
      (builtins.readFile ../../../../../../../vars/shared/woodpecker-default-agent-secret/woodpecker-default-agent-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/woodpecker-forgejo-oauth-secret/woodpecker-forgejo-oauth-secret/value)
    ];

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };

    helm.releases.${name} = {
      chart = charts.forgejo.forgejo;
      values = {};
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
