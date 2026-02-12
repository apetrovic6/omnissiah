{
  charts,
  config,
  ...
}: let
  namespace = "vikunja";
  domain = config.noosphere.domain;
  db-cluster-name = "pg-vikunja";
  objectStoreName = "vikunja-object-store";
in {
  imports = [
    ../../../_modules/templates/garage-object-store.nix
    ../../../_modules/templates/database-template.nix
  ];

  applications.vikunja = {
    inherit namespace;
    createNamespace = true;

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };

    templates.cnpg-database-cluster.vikunja = {
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

          # bootstrap.recovery.source = "origin";

          # externalClusters = [
          #   {
          #     plugin = {
          #       parameters = {
          #         barmanObjectName = objectStoreName;
          #         serverName = "pg-yarr-restored";
          #       };
          #     };
          #   }
          # ];
        };
      };

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

    helm.releases.vikunja = {
      chart = charts.go-vikunja.vikunja;

      values.vikunja = {
        ingress = {
          main = {
            enabled = true;
            annotations = {
              "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
              "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
              "glance/name" = "Vikunja";
              "glance/icon" = "di:vikunja";
              "glance/url" = "https://vikunja.${domain}";
              "glance/description" = "Project Planning";
              "glance/id" = "vikunja";
              "glance/parent" = "vikunja";
              "category" = "productivity";
            };

            hosts = [
              {
                host = "vikunja.${domain}";
                paths = [{path = "/";}];
              }
            ];

            tls = [
              {
                secretName = "vikunja-tls";
                hosts = ["vikunja.${domain}"];
              }
            ];
          };
        };

        persistence.database.enabled = false;
        
        configMaps = {
          config = {
            enabled = true;
            data = {
              "config.yml" = ''
                service:
                  publicurl: "https://vikunja.${domain}"
              '';
            };
          };
        };

        env = {
          VIKUNJA_DATABASE_TYPE = "postgres";

          VIKUNJA_DATABASE_HOST = {
            valueFrom.secretKeyRef = {
              name = "${db-cluster-name}-app";
              key = "host";
            };

          };
            VIKUNJA_DATABASE_USER = {
              valueFrom.secretKeyRef = {
                name = "${db-cluster-name}-app";
                key = "user";
              };

            };
              VIKUNJA_DATABASE_PASSWORD = {
                valueFrom.secretKeyRef = {
                  name = "${db-cluster-name}-app";
                  key = "password";
                };
              };

              VIKUNJA_DATABASE_DATABASE = "app";
        };
      };
    };
  };
}
