{pkgs, config, ...}:
let
  keycloakVersion = "26.5.0";
  keycloakCrds1 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${keycloakVersion}/kubernetes/keycloaks.k8s.keycloak.org-v1.yml";
    hash = "sha256-hWZ5SkIaI7ZDrHoFPgDpE8InoFGe3EPwEJfzeYO7kV8=";
  };

  keycloakCrds2 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${keycloakVersion}/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml";
    hash = "sha256-MlKbZ7Mst/cKVKDoaL8Jb3Ul13tmcHIiK0bSWLlLaDY=";
  };

keycloakOperator = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${keycloakVersion}/kubernetes/kubernetes.yml";
    hash = "sha256-ROYGpL+GpFo042JuPE1gY7eZO8blhucyYJDBfY248kg=";
  };

  namespace = "keycloak";
  db-cluster-name = "pg-keycloak";
  objectStoreName = "keycloak-object-store";
  barmanPluginName = "barman-cloud.cloudnative-pg.io";
  domain = config.noosphere.domain;
  
  in
 {
   applications.keycloak = {
      inherit namespace;
      createNamespace = true;

      yamls = [
        (builtins.readFile keycloakCrds1)
        (builtins.readFile keycloakCrds2)
        (builtins.readFile keycloakOperator)
      ];

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };

    
    resources.ingresses.keycloak-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Keycloak";
          "glance/icon" = "di:keycloak";
          "glance/url" = "https://keycloak.${domain}";
          "glance/description" = "Identity Provider";
          "glance/id" = "keycloak";
          "glance/parent" = "keycloak";
          "category" = "security";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "keycloak-tls";
            hosts = ["keycloak.${domain}"];
          }
        ];

        rules = [
          {
            host = "keycloak.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "keycloak";
                  port.number = 80;
                };
              }
            ];
          }
        ];
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
        instances = 2;
        storage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "1Gi";
        };

        bootstrap.recovery.source = "origin";

        externalClusters = [
          {
            name = "origin";
            plugin = {
              name = barmanPluginName;
              parameters = {
                barmanObjectName = objectStoreName;
                serverName = "pg-yarr";
              };
            };
          }
        ];

        walStorage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "1Gi";
        };

        plugins = [
          {
            name = barmanPluginName;
            isWALArchiver = true;
            parameters.barmanObjectName = objectStoreName;
          }
        ];

        postgresql.parameters = {
          shared_buffers = "1GB";
          max_connections = "200";
          log_statement = "ddl";
        };

        monitoring.enablePodMonitor = true;
      };
    };   };

}
