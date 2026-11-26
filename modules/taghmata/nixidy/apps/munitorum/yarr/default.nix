# The yarr media stack: Seerr, the *arr applications, SABnzbd and Aurral, in one
# namespace and on one PostgreSQL cluster.
#
# What they share is declared here: the namespace, the pg-yarr cluster with a
# database and role per application, and the object store its backups go to.
# Those resources are defined on the `seerr` application, not on one of their
# own, because that is where they have always been rendered
# (manifests/prod/seerr). Moving them to another application would make
# ArgoCD prune them from one and create them in the other, and that includes
# the database cluster.
{...}: {
  nixidy.envs.prod.apps.yarr = {lib, ...}: let
    namespace = "yarr";
    db-cluster-name = "pg-yarr-2";
    objectStoreName = "yarr-object-store";

    arr = args: import ./_arr.nix (args // {inherit lib;});
  in {
    imports = [
      ../../../_modules/templates/garage-object-store.nix
      ../../../_modules/templates/database-template.nix
      ./_seerr
      ./_sabnzbd
      ./_aurral
      (arr {
        name = "radarr";
        port = 7878;
        description = "Pvr";
        # Lower case here and upper case on the others. Kept as deployed: the
        # variable names are part of the rendered Deployment.
        envPrefix = "radarr";
      })
      (arr {
        name = "sonarr";
        port = 8989;
        description = "Pvr";
      })
      (arr {
        name = "lidarr";
        port = 8686;
        description = "Music collection manager";
      })
      (arr {
        name = "prowlarr";
        port = 9696;
        description = "Indexer Management";
        mediaLibrary = false;
      })
      (arr {
        name = "bazarr";
        port = 6767;
        description = "Subtitle manager";
        dbEnv = "bazarr";
        # Audio-based subtitle sync (ffsubsync) decodes whole audio tracks;
        # keep it from taking over a 4-core node.
        resources = {
          requests.cpu = "100m";
          limits.cpu = "1";
        };
      })
    ];

    # Passed to the applications above as the `yarr` module argument.
    _module.args.yarr = {
      inherit namespace;
      dbClusterName = db-cluster-name;
    };

    applications.seerr = {
      templates.garageObjectStore."${objectStoreName}" = {
        inherit namespace;
        # Migrated off the failing NFS-backed `garage` cluster onto the
        # operator-managed `garage-backup` cluster (its yarr bucket/key are
        # provisioned and the creds are reflected as yarr-s3-secret-key).
        awsDefaultRegion = "backup";
        destinationPath = "s3://yarr/backups";
        endpointUrl = "http://garage-backup.garage-operator.svc.cluster.local:3900";
        S3Credentials = {
          accessKeyId = {
            name = "yarr-s3-secret-key";
            key = "MINIO_ACCESS_KEY_ID";
          };
          secretAccessKey = {
            name = "yarr-s3-secret-key";
            key = "MINIO_SECRET_ACCESS_KEY";
          };
        };
      };

      resources.namespaces.yarr = {
        metadata = {
          name = namespace;
          labels.name = namespace;
        };
      };

      templates.cnpg-database-cluster.yarr-2 = {
        inherit namespace;
        overrideObjectStore = objectStoreName;
        cluster = {
          spec = {
            # Previously unset, so these inherited the template's 1Gi default while
            # the live PVCs had been expanded to 10Gi out of band. Pinned to the
            # real sizes, with WAL raised to 20Gi: archiving to the dead `garage`
            # cluster filled the 10Gi WAL volumes completely, which blocks
            # PostgreSQL startup and leaves no room to drain the backlog.
            storage.size = "10Gi";
            walStorage.size = "20Gi";

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

              {
                name = "radarr";
                ensure = "present";
                comment = "Radarr User";
                login = true;
                superuser = false;
                passwordSecret.name = "pg-radarr-password";
              }

              {
                name = "lidarr";
                ensure = "present";
                comment = "Lidarr User";
                login = true;
                superuser = false;
                passwordSecret.name = "pg-lidarr-password";
              }

              {
                name = "bazarr";
                ensure = "present";
                comment = "Bazarr User";
                login = true;
                superuser = false;
                passwordSecret.name = "pg-bazarr-password";
              }
            ];

            externalClusters = [
              {
                plugin = {
                  parameters = {
                    barmanObjectName = objectStoreName;
                    serverName = "pg-yarr-1";
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
                "argocd.argoproj.io/sync-options" = "Prune=false";
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
                "argocd.argoproj.io/sync-options" = "Prune=false";
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
                "argocd.argoproj.io/sync-options" = "Prune=false";
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
                "argocd.argoproj.io/sync-options" = "Prune=false";
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
                "argocd.argoproj.io/sync-options" = "Prune=false";
              };
            };
            spec = {
              name = "sonarr-logs";
              owner = "sonarr";
              cluster.name = "${db-cluster-name}";
            };
          }

          {
            name = "db-radarr";

            metadata = {
              annotations = {
                "argocd.argoproj.io/sync-options" = "Prune=false";
              };
            };
            spec = {
              name = "radarr";
              owner = "radarr";
              cluster.name = "${db-cluster-name}";
            };
          }

          {
            name = "db-radarr-logs";

            metadata = {
              annotations = {
                "argocd.argoproj.io/sync-options" = "Prune=false";
              };
            };
            spec = {
              name = "radarr-logs";
              owner = "radarr";
              cluster.name = "${db-cluster-name}";
            };
          }
          {
            name = "db-lidarr";

            metadata = {
              annotations = {
                "argocd.argoproj.io/sync-options" = "Prune=false";
              };
            };
            spec = {
              name = "lidarr";
              owner = "lidarr";
              cluster.name = "${db-cluster-name}";
            };
          }

          {
            name = "db-lidarr-logs";

            metadata = {
              annotations = {
                "argocd.argoproj.io/sync-options" = "Prune=false";
              };
            };
            spec = {
              name = "lidarr-logs";
              owner = "lidarr";
              cluster.name = "${db-cluster-name}";
            };
          }

          {
            name = "db-bazarr";

            metadata = {
              annotations = {
                "argocd.argoproj.io/sync-options" = "Prune=false";
              };
            };
            spec = {
              name = "bazarr";
              owner = "bazarr";
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

    garage.keys.yarr = {
      cluster = "backup";
      secret.namespace = "yarr";
    };
  };
}
