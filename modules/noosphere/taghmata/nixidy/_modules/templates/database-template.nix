{lib, ...}: let
  inherit (lib) mkOption types;
  barmanPluginName = "barman-cloud.cloudnative-pg.io";
  defaultStorageClass = "longhorn-cnpg-strict-local";
  defaultStorageSize = "2Gi";
in {
  templates.cnpg-database-cluster = {
    options = {
      cluster = {
        annotations = mkOption {
          type = types.nullOr types.attrSet;
          default = {
            "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
            "argocd.proj.io/sync-hook" = "PreSync";
          };
          description = "Cluster Annotations.";
        };

        spec = {
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
              descripon = "Storage size.";
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
              descripon = "Storage size.";
            };
          };

          overrideObjectStore = mkOption {
            type = types.str;
            default = "";
            description = "Barman object store for the cluster";
          };

          bootstrap.recovery.source = mkOption {
            type = types.str;
            default = "origin";
            description = "Recovery source for the cluster";
          };

          externalClusters = mkOption {
            type = types.listOf (types.submodule ({...}: {
              options = {
                name = mkOption {
                  type = types.str;
                  default = "origin";
                  example = "origin";
                };

                plugin = mkOption {
                  type = types.attrsOf (types.submodule ({...}: {
                    options = {
                      name = mkOption {
                        type = types.str;
                        default = barmanPluginName;
                        description = "Name of the plugin";
                      };
                      parameters = mkOption {
                        type = types.attrsOf (types.submodule ({...}: {
                          options = {
                            barmanObjectName = mkOption {
                              type = types.str;
                              example = "my-object-store";
                              default = "";
                              description = "Name of the object store";
                            };
                            serverName = mkOption {
                              type = types.str;
                              default = "";
                              description = "Name of the postgres cluster to restore";
                            };
                          };
                        }));
                      };
                    };
                  }));
                };
              };
            }));
          };

          plugins = mkOption {
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
            type = types.attrSet;
            default = {
              shared_buffers = "1GB";
              max_connections = "200";
              log_statement = "ddl";
            };
          };

          managed.roles = mkOption {
            type = types.listOf (types.submodule ({...}: {
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
                  type = types.string;
                  default = "";
                };
              };
            }));
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
            namespace = mkOption {
              type = types.str;
              default = "";
              description = "Namespace for the DB deployment";
            };

            annotations = {
              type = types.attrSet;
              default = {
                "argocd.proj.io/sync-options" = "Prune=false";
              };
              description = "Annotations for the database declarations";
            };

            spec = {
              type = types.attrsOf (types.submodule ({...}: {
                options = {
                  name = mkOption {
                    type = types.str;
                    default = "";
                    description = "Name of the database.";
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
              }));
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
                type = types.attrsOf (types.submodule ({...}: {
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
                  };
                }));
              };
            };
          }));
        };

        onDemandBackups = mkOption {
          type = types.listOf (types.submodule ({...}: {
            options = {
              metadata.namespace = mkOption {
                type = types.str;
                default = "";
                description = "Namespace for the scheduled backup";
              };

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
        namespace = cfg.cluster.namespace;
        annotations = cfg.cluster.annotations;
      };
      spec = cfg.cluster.spec;
      walStorage = cfg.cluster.walStorage;
      plugins = cfg.cluster.plugins ++ cfg.cluster.extraPlugins;
      postgresql.parameters = cfg.cluster.postgresql.parameters;
      monitoring.enablePodMonitor = cfg.cluster.enablePodMonitor;
      managed.roles = cfg.cluster.managed.roles;
      externalClusters = cfg.cluster.externalClusters;
    };


  };
}
