{config, ...}: let
  namespace = "unifi";
  domain = config.noosphere.domain;
  mongoDBName = "unifi-mongodb";
  objectStoreName = "unifi-object-store";
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
        image = "percona/percona-server-mongodb:7.0.14-8";

        # UniFi works best with 3 replicas for durability
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

            expose = {
              enabled = false;
            };

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

        secrets = {
          users = "unifi-mongodb-password";
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
        labels = {
          app = "unifi";
        };
      };

      spec = {
        replicas = 1; # UniFi can only run 1 replica
        strategy = {
          type = "Recreate";
        };

        selector = {
          matchLabels = {
            app = "unifi";
          };
        };

        template = {
          metadata = {
            labels = {
              app = "unifi";
            };
          };

          spec = {
            containers = [
              {
                name = "unifi";
                image = "lscr.io/linuxserver/unifi-network-application:latest";

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
                        key = "password";
                      };
                    };
                  }
                  {
                    name = "MONGO_HOST";
                    value = "${mongoDBName}-rs0";
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
                ];

                ports = [
                  {
                    name = "web-ui";
                    containerPort = 8443;
                    protocol = "TCP";
                  }
                  {
                    name = "controller";
                    containerPort = 8080;
                    protocol = "TCP";
                  }
                  {
                    name = "speedtest";
                    containerPort = 6789;
                    protocol = "TCP";
                  }
                  {
                    name = "stun";
                    containerPort = 3478;
                    protocol = "UDP";
                  }
                  {
                    name = "ap-discovery";
                    containerPort = 10001;
                    protocol = "UDP";
                  }
                  {
                    name = "device-comms";
                    containerPort = 8880;
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
        name = "unifi";
      };
      spec = {
        type = "ClusterIP";
        selector = {
          app = "unifi";
        };
        ports = [
          {
            name = "web-ui";
            port = 8443;
            targetPort = 8443;
            protocol = "TCP";
          }
          {
            name = "controller";
            port = 8080;
            targetPort = 8080;
            protocol = "TCP";
          }
          {
            name = "speedtest";
            port = 6789;
            targetPort = 6789;
            protocol = "TCP";
          }
        ];
      };
    };

    # Service for UniFi device communication (LoadBalancer for direct access)
    resources.services.unifi-devices = {
      metadata = {
        inherit namespace;
        name = "unifi-devices";
      };
      spec = {
        type = "LoadBalancer";
        selector = {
          app = "unifi";
        };
        ports = [
          {
            name = "stun";
            port = 3478;
            targetPort = 3478;
            protocol = "UDP";
          }
          {
            name = "ap-discovery";
            port = 10001;
            targetPort = 10001;
            protocol = "UDP";
          }
          {
            name = "device-comms";
            port = 8880;
            targetPort = 8880;
            protocol = "TCP";
          }
        ];
      };
    };

    # Ingress for web UI
    resources.ingresses.unifi = {
      metadata = {
        inherit namespace;
        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "traefik.ingress.kubernetes.io/router.tls" = "true";
          # UniFi uses self-signed certs internally
          "traefik.ingress.kubernetes.io/service.serversscheme" = "https";
          "glance/name" = "UniFi";
          "glance/icon" = "di:unifi";
          "glance/url" = "https://unifi.${domain}";
          "glance/description" = "Network Controller";
          "glance/id" = "unifi";
          "glance/parent" = "unifi";
          "category" = "infrastructure";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "unifi-tls";
            hosts = ["unifi.${domain}"];
          }
        ];

        rules = [
          {
            host = "unifi.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "unifi";
                  port.number = 8443;
                };
              }
            ];
          }
        ];
      };
    };
  };
}
