{
  config,
  charts,
  ...
}: let
  namespace = "unifi";
  domain = config.noosphere.domain;
  mongoDBName = "unifi-mongodb";
in {
  applications.unifi-network = {
    inherit namespace;
    createNamespace = true;

    # MongoDB cluster password secret (you'll need to generate this)
    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/unifi-mongodb-password/unifi-mongodb-password/value)
    ];

    # MongoDB Community cluster
    resources."mongodbcommunity.mongodb.com".v1.MongoDBCommunity.${mongoDBName} = {
      metadata = {
        inherit namespace;
      };

      spec = {
        members = 3; # Single node for unifi
        type = "ReplicaSet";
        version = "7.0.12"; # Or your preferred version

        security = {
          authentication = {
            modes = ["SCRAM"];
          };
        };

        users = [
          {
            name = "unifi";
            db = "unifi";
            passwordSecretRef = {
              name = "unifi-mongodb-password";
              key = "password";
            };
            roles = [
              {
                name = "dbOwner";
                db = "unifi";
              }
              {
                name = "clusterMonitor";
                db = "admin";
              }
            ];
            scramCredentialsSecretName = "unifi-mongodb-scram";
          }
        ];

        additionalMongodConfig = {
          "storage.wiredTiger.engineConfig.journalCompressor" = "snappy";
          "net.tls.mode" = "disabled";
        };

        statefulSet = {
          spec = {
            volumeClaimTemplates = [
              {
                metadata = {
                  name = "data-volume";
                };
                spec = {
                  storageClassName = "longhorn";
                  accessModes = ["ReadWriteOnce"];
                  resources = {
                    requests = {
                      storage = "10Gi";
                    };
                  };
                };
              }
              {
                metadata = {
                  name = "logs-volume";
                };
                spec = {
                  storageClassName = "longhorn";
                  accessModes = ["ReadWriteOnce"];
                  resources = {
                    requests = {
                      storage = "2Gi";
                    };
                  };
                };
              }
            ];
          };
        };
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
        replicas = 3;
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
                    value = "${mongoDBName}-svc";
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
