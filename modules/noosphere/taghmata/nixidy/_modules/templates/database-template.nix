{lib, ...}: let
  inherit (lib) mkOption types;
  barmanPluginName = "barman-cloud.cloudnative-pg.io";
  defaultStorageClass = "longhorn-cnpg-strict-local";
  defaultStorageSize = "1Gi";
in {
  templates.cnpg-database-cluster = {
    options = {
      overrideObjectStore = mkOption {
        type = types.str;
        default = "";
        description = "Barman object store for the cluster";
      };

      cluster = {
        annotations = mkOption {
          type = types.nullOr types.attrs;
          default = {
            "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
            "argocd.proj.io/sync-hook" = "PreSync";
          };
          description = "Cluster Annotations.";
        };

        spec = {
          imageName = mkOption {
            type = types.str;
            default = "ghcr.io/cloudnative-pg/postgresql:18.1-minimal-trixie";
            description = "PostgreSQL image to use for the cluster.";
          };

          primaryUpdateStrategy = mkOption {
            type = types.str;
            default = "unsupervised";
            description = "Update strategy.";
          };

          instances = mkOption {
            type = types.int;
            default = 3;
            description = "Number of Postgres instances";
          };

          storage = {
            storageClass = mkOption {
              type = types.str;
              default = defaultStorageClass;
              description = "Storage class for the cluster";
            };

            size = mkOption {
              type = types.str;
              default = defaultStorageSize;
              description = "Storage size.";
            };
          };

          walStorage = {
            storageClass = mkOption {
              type = types.str;
              default = defaultStorageClass;
              description = "Storage class for the cluster";
            };

            size = mkOption {
              type = types.str;
              default = defaultStorageSize;
              description = "Storage size.";
            };
          };

          bootstrap.recovery.source = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Recovery source for the cluster";
          };

          externalClusters = mkOption {
            type = types.nullOr (types.listOf (types.submodule ({...}: {
              options = {
                name = mkOption {
                  type = types.str;
                  default = "origin";
                };

                plugin = mkOption {
                  # single plugin object
                  type = types.submodule ({...}: {
                    options = {
                      name = mkOption {
                        type = types.str;
                        default = barmanPluginName;
                        description = "Name of the plugin";
                      };

                      parameters = mkOption {
                        # single parameters object
                        type = types.submodule ({...}: {
                          options = {
                            barmanObjectName = mkOption {
                              type = types.str;
                              default = "";
                            };
                            serverName = mkOption {
                              type = types.str;
                              default = "";
                            };
                          };
                        });

                        default = {}; # allows omitting parameters entirely
                      };
                    };
                  });

                  default = {}; # allows omitting plugin entirely
                };
              };
            })));

            default = null;
          };
          plugins = mkOption {
            type = types.listOf (types.submodule ({...}: {
              options = {
                name = mkOption {
                  type = types.str;
                  default = barmanPluginName;
                  example = barmanPluginName;
                };

                isWALArchiver = mkOption {
                  type = types.bool;
                  default = false;
                };

                parameters = mkOption {
                  type = types.attrsOf (types.oneOf [
                    types.str
                    types.int
                    types.float
                  ]);

                  default = {barmanObjectName = "";};
                  example = {barmanObjectName = "my-object-store";};
                };
              };
            }));
          };

          extraPlugins = mkOption {
            default = [];
            type = types.listOf (types.submodule ({...}: {
              options = {
                name = mkOption {
                  type = types.str;
                  default = barmanPluginName;
                  example = barmanPluginName;
                };

                isWalArchiver = mkOption {
                  type = types.bool;
                  default = false;
                };

                parameters = mkOption {
                  type = types.attrsOf (types.oneOf [
                    types.str
                    types.int
                    types.float
                  ]);

                  default = {barmanObjectName = "";};
                  example = {barmanObjectName = "my-object-store";};
                };
              };
            }));
          };

          postgresql.parameters = mkOption {
            type = types.attrs;
            default = {
              shared_buffers = "1GB";
              max_connections = "200";
              log_statement = "ddl";
            };
          };

          managed.roles = mkOption {
            type = types.nullOr (types.listOf (types.submodule ({...}: {
              options = {
                name = mkOption {
                  type = types.str;
                  default = "";
                  description = "DB User";
                };

                ensure = mkOption {type = types.enum ["present" "absent"];};
                comment = mkOption {
                  type = types.str;
                  default = "";
                };
                login = mkOption {
                  type = types.bool;
                  default = false;
                };
                superuser = mkOption {
                  type = types.bool;
                  default = false;
                };
                passwordSecret.name = mkOption {
                  type = types.str;
                  default = "";
                };
              };
            })));
            default = null;
            description = "Add a list of users.";
          };

          monitoring.enablePodMonitor = mkOption {
            type = types.bool;
            default = true;
            description = "Enable pod monitoring";
          };
        };
      };

      namespace = mkOption {
        type = types.str;
        default = "";
        description = "Namespace for the DB deployment";
      };

      databases = mkOption {
        type = types.listOf (types.submodule ({...}: {
          options = {
            name = mkOption {
              type = types.str;
              default = "";
              description = "Name of the DB";
            };

            metadata.annotations = mkOption {
              type = types.attrs;
              default = {
                "argocd.proj.io/sync-options" = "Prune=false";
              };
              description = "Annotations for the database declarations";
            };

            spec = {
              name = mkOption {
                type = types.str;
                default = "";
                description = "User name";
              };
              owner = mkOption {
                type = types.str;
                default = "";
                description = "Owner of the database.";
              };
              cluster.name = mkOption {
                type = types.str;
                default = "";
                description = "Name of the cluster the database belongs to.";
              };
            };
          };
        }));
      };

      backups = {
        scheduledBackups = mkOption {
          type = types.listOf (types.submodule ({...}: {
            options = {
              metadata.namespace = mkOption {
                type = types.str;
                default = "";
                description = "Namespace for the scheduled backup";
              };

              spec = mkOption {
                type = types.submodule ({...}: {
                  options = {
                    schedule = mkOption {
                      type = types.str;
                      default = "0 2 0 * * *";
                      description = "Cron job schedule that will backup the cluster in the given schedule";
                    };

                    method = mkOption {
                      type = types.str;
                      default = "plugin";
                    };
                    backupOwnerReference = mkOption {
                      type = types.str;
                      default = "self";
                      description = "Owner of the deployment";
                    };
                    cluster.name = mkOption {
                      type = types.str;
                      default = "";
                    };
                    pluginConfiguration.name = mkOption {
                      type = types.str;
                      default = barmanPluginName;
                    };
                    immediate = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Whether to trigger an immediate backup";
                    };
                  };
                });
              };
            };
          }));
        };

        onDemandBackups = mkOption {
          type = types.listOf (types.submodule ({...}: {
            options = {
              spec = {
                method = mkOption {
                  type = types.str;
                  default = "plugin";
                };
                cluster.name = mkOption {
                  type = types.str;
                  default = "";
                };
                pluginConfiguration.name = mkOption {
                  type = types.str;
                  default = barmanPluginName;
                };
              };
            };
          }));
        };
      };
    };

    output = {
      name,
      config,
      ...
    }: let
      cfg = config;
    in {
      clusters."pg-${name}" = {
        metadata = {
          namespace = cfg.namespace;
          annotations = cfg.cluster.annotations;
          # Labels that will be inherited by the PodMonitor
          labels = {
            release = "kube-prometheus-stack";
          };
        };
        spec = let
          baseSpec = cfg.cluster.spec;
          basePlugins = baseSpec.plugins or [];
          extraPlugins = baseSpec.extraPlugins or [];

          # Remove bootstrap if recovery source is not set
          # Remove managed if roles is not set
          attrsToRemove =
            ["extraPlugins"]
            ++ lib.optional (cfg.cluster.spec.bootstrap.recovery.source == null) "bootstrap"
            ++ lib.optional (cfg.cluster.spec.managed.roles == null) "managed";
        in
          (lib.removeAttrs baseSpec attrsToRemove)
          // {
            plugins = basePlugins ++ extraPlugins;

            # Enable backup functionality (required even when using plugins)
            backup = {
              target = "prefer-standby";
              retentionPolicy = "30d";
            };

            monitoring = {
              enablePodMonitor = baseSpec.monitoring.enablePodMonitor;
              # Custom queries from default monitoring configmap
              customQueriesConfigMap = [
                {
                  name = "cnpg-default-monitoring";
                  key = "queries";
                }
              ];
              podMonitorMetricRelabelings = [
                {
                  sourceLabels = ["cluster"];
                  targetLabel = "cnpg_cluster";
                  action = "replace";
                }
              ];
              podMonitorRelabelings = [
                {
                  sourceLabels = ["__meta_kubernetes_pod_name"];
                  targetLabel = "pod";
                  action = "replace";
                }
              ];
            };
          };
      };

      databases = lib.listToAttrs (map (
          db: let
            base = lib.removeAttrs db ["name"];
          in
            lib.nameValuePair db.name (base
              // {
                metadata =
                  (base.metadata or {})
                  // {
                    namespace = cfg.namespace;
                  };
              })
        )
        cfg.databases);

      scheduledBackups = lib.listToAttrs (
        lib.imap0 (
          i: backup:
            lib.nameValuePair "pg-${name}-scheduled-backup-${toString i}" {
              metadata = {
                namespace = backup.metadata.namespace or cfg.namespace;
              };
              spec =
                {
                  # Ensure method and pluginConfiguration are always set
                  method = backup.spec.method or "plugin";
                  pluginConfiguration.name = backup.spec.pluginConfiguration.name or barmanPluginName;
                }
                // backup.spec
                // {
                  cluster.name = "pg-${name}";
                };
            }
        )
        cfg.backups.scheduledBackups
      );

      backups = lib.listToAttrs (
        lib.imap0 (
          i: backup:
            lib.nameValuePair "pg-${name}-on-demand-backup-${toString i}" {
              metadata.namespace = cfg.namespace;
              spec = {
                # Ensure method and pluginConfiguration are always set
                method = backup.spec.method or "plugin";
                cluster.name = "pg-${name}";
                pluginConfiguration.name = backup.spec.pluginConfiguration.name or barmanPluginName;
              };
            }
        )
        cfg.backups.onDemandBackups
      );
    };
  };
}
