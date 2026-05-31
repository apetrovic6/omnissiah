{
  domain,
  namespace,
  ...
}: {
  applications.garage-operator = {
    resources.garageClusters.garage-backup = {
      metadata = {inherit namespace;};
      spec = {
        zone = "main";

        storage = {
          replicas = 3;
          data = {
            size = "300Gi";
            storageClassName = "synology-nfs";
          };
          metadata = {
            size = "20Gi";
            storageClassName = "synology-nfs";
          };
        };

        database = {engine = "sqlite";};
        replication = {factor = 3;};

        admin = {
          bindPort = 3903;
          adminTokenSecretRef = {
            name = "garage-backup-admin-token";
            key = "admin-token";
          };
        };

        network = {
          rpcBindPort = 3901;
          service.type = "ClusterIP";
          rpcSecretRef = {
            name = "garage-backup-rpc-secret";
            key = "rpc-secret";
          };
        };

        discovery.kubernetes = {enabled = true;};

        layoutManagement = {
          autoApply = true;
          minNodesHealthy = 2;
        };
        layoutPolicy = "Auto";

        s3Api = {
          bindPort = 3900;
          region = "backup";
          rootDomain = ".s3.backup.garage.${domain}";
        };
      };
    };

    resources.services.garage-backup-s3-api = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-backup";
        };
        ports = [
          {
            name = "s3";
            port = 3900;
            targetPort = 3900;
          }
        ];
      };
    };

    resources.services.garage-backup-admin = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-backup";
        };
        ports = [
          {
            name = "admin";
            port = 3903;
            targetPort = 3903;
          }
        ];
      };
    };

    resources.ingresses.garage-backup-s3-api = {
      metadata = {
        inherit namespace;
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
        };
      };
      spec = {
        ingressClassName = "traefik";
        rules = [
          {
            host = "s3.backup.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-backup-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
          {
            host = "*.s3.backup.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-backup-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
        ];
        tls = [
          {
            secretName = "garage-operator-s3-tls";
            hosts = ["s3.backup.garage.${domain}" "*.s3.backup.garage.${domain}"];
          }
        ];
      };
    };

    resources.garageKeys.pocket-id = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "pocket-id";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "pocket-id-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "pocket-id";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "pocket-id";
          };
        };
      };
    };

    resources.garageBuckets.pocket-id = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
        # keyPermissions = [
        #   {
        #     keyRef = "pocket-id";
        #     read = true;
        #     write = true;
        #     owner = true;
        #   }
        # ];
      };
    };
  };
}
