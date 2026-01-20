{config, ...}: let
  namespace = "unifi-controller";
  domain = config.noosphere.domain;
  mongoDBName = "unifi-mongodb";
  objectStoreName = "unifi-object-store";

  labels = {
    app = "unifi-controller";
    "app.kubernetes.io/instance" = "unifi-controller";
  };
in {
  # imports = [
  #   ../../../../_modules/templates/garage-object-store.nix
  # ];

  applications.unifi-network = {
    inherit namespace;
    createNamespace = true;

    # Secrets: MongoDB password and S3 credentials
    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/unifi-mongodb-password/unifi-mongodb-password/value)
      (builtins.readFile ../../../../../../../vars/shared/unifi-s3-secret-key/unifi-s3-secret-key/value)
    ];

    # # Garage Object Store for backups
    # templates.garageObjectStore.${objectStoreName} = {
    #   inherit namespace;
    # };

    # Percona MongoDB cluster
    resources."psmdb.percona.com".v1.PerconaServerMongoDB.${mongoDBName} = {
      metadata = {
        inherit namespace;
      };

      spec = {
        crVersion = "1.18.0";
        image = "percona/percona-server-mongodb:8.0.17-6";

        enableVolumeExpansion = true;

        tls.mode = "allowTLS";

        replsets = [
          {
            name = "rs0";
            size = 3;

            affinity = {
              antiAffinityTopologyKey = "kubernetes.io/hostname";
            };

            podDisruptionBudget = {
              maxUnavailable = 1;
            };

            # expose = {
            # enabled = false;
            # };

            # nonvoting = {
            #   enabled = false;
            # };

            # arbiter = {
            #   enabled = false;
            # };

            resources = {
              limits = {
                cpu = "1000m";
                memory = "2Gi";
              };
              requests = {
                cpu = "100m";
                memory = "512Mi";
              };
            };

            volumeSpec = {
              persistentVolumeClaim = {
                storageClassName = "longhorn";
                accessModes = ["ReadWriteOnce"];
                resources = {
                  requests = {
                    storage = "10Gi";
                  };
                };
              };
            };
          }
        ];

        secrets.users = "unifi-mongodb-password";

        users.unifi = {
          name = "unifi";
          db = "admin";
          passwordSecretRef = {
            name = "unifi-mongodb-password";
            key = "unifi";
          };
          roles = {
            readWrite-unifi = {
              name = "readWrite";
              db = "unifi";
            };
            dbAdmin-unifi = {
              name = "dbAdmin";
              db = "unifi";
            };
            readWrite-unifi_stat = {
              name = "readWrite";
              db = "unifi_stat";
            };
            dbAdmin-unifi_stat = {
              name = "dbAdmin";
              db = "unifi_stat";
            };
            readWrite-unifi_audit = {
              name = "readWrite";
              db = "unifi_audit";
            };
            dbAdmin-unifi_audit = {
              name = "dbAdmin";
              db = "unifi_audit";
            };
          };
        };

        # Automated backups to Garage S3
        # backup = {
        #   enabled = true;
        #   image = "percona/percona-backup-mongodb:2.7.0";
        #   serviceAccountName = "percona-server-mongodb-operator";

        #   storages = {
        #     garage-s3 = {
        #       type = "s3";
        #       s3 = {
        #         bucket = "mongo-backup-bucket";
        #         region = "garage";
        #         credentialsSecret = "unifi-s3-secret-key";
        #         endpointUrl = "http://garage.garage.svc.cluster.local:3900";
        #       };
        #     };
        #   };

        #   pitr = {
        #     enabled = true;
        #     oplogSpanMin = 10;
        #   };

        #   tasks = [
        #     {
        #       name = "daily-backup";
        #       enabled = true;
        #       schedule = "0 2 * * *"; # 2 AM daily
        #       keep = 7;
        #       storageName = "garage-s3";
        #       compressionType = "gzip";
        #     }
        #   ];
        # };
      };
    };

    # UniFi Network Controller deployment
    resources.deployments.unifi = {
      metadata = {
        inherit namespace;
        inherit labels;
      };

      spec = {
        replicas = 1; # UniFi can only run 1 replica
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 1;
            maxUnavailable = 1;
          };
        };

        selector = {
          matchLabels = {
            app = "unifi-controller";
          };
        };

        template = {
          metadata = {
            labels = {
              app = "unifi-controller";
            };
          };

          spec = {
            containers = [
              {
                name = "unifi";
                image = "lscr.io/linuxserver/unifi-network-application:20.10.25";

                env = [
                  {
                    name = "PUID";
                    value = "1000";
                  }
                  {
                    name = "PGID";
                    value = "1000";
                  }
                  {
                    name = "TZ";
                    value = "Europe/London";
                  }
                  {
                    name = "MONGO_USER";
                    value = "unifi";
                  }
                  {
                    name = "MONGO_PASS";
                    valueFrom = {
                      secretKeyRef = {
                        name = "unifi-mongodb-password";
                        key = "unifi";
                      };
                    };
                  }
                  {
                    name = "MONGO_HOST";
                    value = "${mongoDBName}-rs0.${namespace}.svc.cluster.local";
                  }
                  {
                    name = "MONGO_PORT";
                    value = "27017";
                  }
                  {
                    name = "MONGO_DBNAME";
                    value = "unifi";
                  }
                  {
                    name = "MONGO_AUTHSOURCE";
                    value = "admin";
                  }
                  {
                    name = "MONGO_REPLICA_SET";
                    value = "rs0";
                  }
                ];

                ports = [
                  {
                    name = "web-ui";
                    containerPort = 8443;
                    protocol = "TCP";
                  }

                  {
                    name = "stun";
                    containerPort = 3478;
                    protocol = "UDP";
                  }

                  {
                    name = "discovery";
                    containerPort = 10001;
                    protocol = "UDP";
                  }

                  {
                    name = "communication";
                    containerPort = 8080;
                    protocol = "TCP";
                  }
                ];

                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                  }
                ];

                resources = {
                  limits = {
                    cpu = "2000m";
                    memory = "2Gi";
                  };
                  requests = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                };
              }
            ];

            volumes = [
              {
                name = "config";
                persistentVolumeClaim = {
                  claimName = "unifi-config";
                };
              }
            ];
          };
        };
      };
    };

    # PVC for UniFi config
    resources.persistentVolumeClaims.unifi-config = {
      metadata = {
        inherit namespace;
      };
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "longhorn";
        resources = {
          requests = {
            storage = "5Gi";
          };
        };
      };
    };

    # Service for UniFi Web UI
    resources.services.unifi-web = {
      metadata = {
        inherit namespace;
        annotations = {
          # "traefik.ingress.kubernetes.io/service.serversscheme" = "https";
          # "traefik.ingress.kubernetes.io/service.serverstransport" = "unifi-unifi-web@kubernetescrd";
          "metallb.universe.tf/allow-shared-ip" = "noosphere";
        };
      };
      spec = {
        type = "LoadBalancer";
        loadBalancerIP = "192.168.1.240";
        selector = {
          app = "unifi-controller";
        };
        ports = [
          {
            name = "web";
            port = 8443;
            targetPort = 8443;
            protocol = "TCP";
          }
          {
            name = "communication";
            port = 8080;
            targetPort = 8080;
            protocol = "TCP";
          }
        ];
      };
    };

    # Service for UniFi device communication (LoadBalancer for direct access)
    resources.services.unifi-devices = {
      metadata = {
        inherit namespace;
        annotations = {
          "metallb.universe.tf/allow-shared-ip" = "unifi-controller";
        };
      };
      spec = {
        type = "LoadBalancer";
        loadBalancerIP = "192.168.1.240";
        selector = {
          app = "unifi-controller";
        };
        ports = [
          {
            name = "stun";
            port = 3478;
            targetPort = 3478;
            protocol = "UDP";
          }
          {
            name = "discovery";
            port = 10001;
            targetPort = 10001;
            protocol = "UDP";
          }
        ];
      };
    };

    resources.middlewares.unifi-default-headers = {
      metadata.namespace = namespace;

      spec = {
        headers = {
          browserXssFilter = true;
          contentTypeNosniff = true;
          forceSTSHeader = true;
          stsIncludeSubdomains = true;
          stsPreload = true;
          stsSeconds = 15552000;
          customFrameOptionsValue = "SAMEORIGIN";
          customRequestHeaders."X-Forwarded-Proto" = "https";
        };
      };
    };

    resources.ingressRoutes.unifi-controller = {
      metadata = {
        inherit namespace;
        annotations = {
          "kubernetes.io/ingress.class" = "traefik-external";
        };
      };

      spec = {
        entryPoints = ["websecure"];
        routes = [
          {
            match = "Host(`unifi.${domain}`)";
            kind = "Rule";
            services = [
              {
                name = "unifi-tcp";
                port = 8443;
                scheme = "https";
              }
            ];

                middlewares= [{name = "default-headers";}];
          }
        ];
        tls.secretName = "unifi-tls";
      };
    };

    # Ingress for web UI
    # resources.ingresses.unifi = {
    #   metadata = {
    #     inherit namespace;
    #     annotations = {
    #       "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
    #       "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
    #       "traefik.ingress.kubernetes.io/router.tls" = "true";
    #       "glance/name" = "UniFi";
    #       "glance/icon" = "di:unifi";
    #       "glance/url" = "https://unifi.${domain}";
    #       "glance/description" = "Network Controller";
    #       "glance/id" = "unifi";
    #       "glance/parent" = "unifi";
    #       "category" = "monitoring";
    #     };
    #   };

    #   spec = {
    #     ingressClassName = "traefik";

    #     tls = [
    #       {
    #         secretName = "unifi-tls";
    #         hosts = ["unifi.${domain}"];
    #       }
    #     ];

    #     rules = [
    #       {
    #         host = "unifi.${domain}";
    #         http.paths = [
    #           {
    #             path = "/";
    #             pathType = "Prefix";
    #             backend.service = {
    #               name = "unifi-web";
    #               port.number = 8443;
    #             };
    #           }
    #         ];
    #       }
    #     ];
    #   };
    # };
  };
}
