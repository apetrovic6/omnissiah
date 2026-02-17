{
  charts,
  config,
  ...
}: let
  namespace = "pocket-id";
  domain = config.noosphere.domain;
  db-cluster-name = "pg-pocket-id";
  objectStoreName = "pocket-id-object-store";
in {
  imports = [
    ../../../_modules/templates/garage-object-store.nix
    ../../../_modules/templates/database-template.nix
  ];

  applications.pocket-id = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/pocket-id-encryption-key/pocket-id-encryption-key/value)
    ];

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };

    helm.releases.pocket-id = {
      chart = charts.anza-labs.pocket-id;
      values = {
        replicaCount = 1;
        host = "id.${domain}";

        pocketID.image = {
          tag = "v2.2.0";
        };

        config = {
          create = true;
          ui = {
            settings = {
              app = {
                emailsVerified = true;
              };
            };
          };
        };

        secret = {
          create = false;
          name = "${db-cluster-name}-app";
        };

        ingress = {
          enabled = true;
          annotations = {
            "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure";
            "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
            "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
            "glance/name" = "Pocket ID";
            "glance/icon" = "di:pocket-id";
            "glance/url" = "https://id.${domain}";
            "glance/description" = "Identity Provider";
            "glance/id" = "pocket-id";
            "glance/parent" = "pocket-id";
            "category" = "security";
          };

          className = "traefik";
          host = "id.${domain}";
          paths = [
            {
              path = "/";
              pathType = "Prefix";
            }
          ];
          tls = [
            {
              secretName = "pocket-id-tls";
              hosts = ["id.${domain}"];
            }
          ];
        };

        timeZone = "Europe/Zagreb";
      };
    };

    resources.statefulSets.pocket-id.spec.template.spec.containers.pocket-id.env = {
      DB_CONNECTION_STRING.valueFrom.secretKeyRef = {
        name = "${db-cluster-name}-app";
        key = "uri";
      };
      ENCRYPTION_KEY.valueFrom.secretKeyRef = {
        name = "pocket-id-encryption-key";
        key = "encryption-key";
      };
    };

    templates.cnpg-database-cluster.pocket-id = {
      inherit namespace;
      overrideObjectStore = objectStoreName;

      cluster = {
        annotations = {
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.proj.io/sync-hook" = "PreSync";
        };

        spec = {
          storage.size = "5Gi";
          walStorage.size = "5Gi";
          plugins = [
            {
              isWALArchiver = true;
              parameters.barmanObjectName = objectStoreName;
            }
          ];
        };
      };

      # Forgejo uses the default database created with the cluster
      databases = [];

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
