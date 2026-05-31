{
  domain,
  namespace,
  ...
}: {
  applications.garage-operator = {
    resources.garageClusters.garage-main = {
      metadata = {inherit namespace;};
      spec = {
        zone = "main";

        storage = {
          replicas = 3;
          data = {
            size = "200Gi";
            storageClassName = "local-path";
          };
          metadata = {
            size = "10Gi";
            storageClassName = "local-path";
          };
        };

        database = {engine = "sqlite";};
        replication = {factor = 3;};

        admin = {
          bindPort = 3903;
          adminTokenSecretRef = {
            name = "garage-main-admin-token";
            key = "admin-token";
          };
        };

        network = {
          rpcBindPort = 3901;
          service.type = "ClusterIP";
          rpcSecretRef = {
            name = "garage-main-rpc-secret";
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
          region = "main";
          rootDomain = ".s3.main.garage.${domain}";
        };
      };
    };

    resources.garageKeys.opentofu = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        bucketPermissions = [
          {
            bucketRef.name = "opentofu";
            read = true;
            write = true;
            owner = true;
          }
        ];
      };
    };

    resources.garageBuckets.opentofu = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        # keyPermissions = [
        #   {
        #     keyRef = "opentofu";
        #     read = true;
        #     write = true;
        #     owner = true;
        #   }
        # ];
      };
    };

    resources.garageKeys.forgejo = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        bucketPermissions = [
          {
            bucketRef.name = "forgejo";
            read = true;
            write = true;
            owner = true;
          }

          {
            bucketRef.name = "forgejo-lfs";
            read = true;
            write = true;
            owner = true;
          }
        ];
        secretTemplate = {
          name = "forgejo-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "forgejo";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "forgejo";
          };
        };
      };
    };

    resources.garageBuckets.forgejo = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        # keyPermissions = [
        #   {
        #     keyRef = "forgejo";
        #     read = true;
        #     write = true;
        #     owner = true;
        #   }
        # ];
      };
    };

    resources.garageBuckets.forgejo-lfs = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        # keyPermissions = [
        #   {
        #     keyRef = "forgejo";
        #     read = true;
        #     write = true;
        #     owner = true;
        #   }
        # ];
      };
    };

    resources.garageKeys.harbor = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";

        bucketPermissions = [
          {
            bucketRef.name = "harbor";
            read = true;
            write = true;
            owner = true;
          }
        ];

      };
    };

    resources.garageBuckets.harbor = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        # keyPermissions = [
        #   {
        #     keyRef = "harbor";
        #     read = true;
        #     write = true;
        #     owner = true;
        #   }
        # ];
      };
    };

    resources.services.garage-s3-api = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-main";
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

    resources.services.garage-main-admin = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-main";
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

    resources.ingresses.garage-s3-api = {
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
            host = "s3.main.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
          {
            host = "*.s3.main.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
        ];
        tls = [
          {
            secretName = "garage-operator-s3-tls";
            hosts = ["s3.main.garage.${domain}" "*.s3.main.garage.${domain}"];
          }
        ];
      };
    };
  };
}
