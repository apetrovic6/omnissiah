{
  charts,
  config,
  ...
}: let
  namespace = "garage-operator";
  domain = config.noosphere.domain;

  cluster-main = import ./cluster-main { inherit config namespace domain; };
in {
  imports = [ cluster-main ];
  applications.garage-operator = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-main-rpc-secret/garage-main-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-main-admin-token/garage-main-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-rpc-secret/garage-backup-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-admin-token/garage-backup-admin-token/value)
    ];

    resources.garageKeys.opentofu = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
      };
    };

    resources.garageBuckets.opentofu = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        keyPermissions = [
          {
            keyRef = "opentofu";
            read = true;
            write = true;
            owner = true;
          }
        ];
      };
    };

    resources.garageKeys.forgejo = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        secretTemplate = {
          name = "forgejo-s3-secret-key";
          namespace = "reflector";
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
        keyPermissions = [
          {
            keyRef = "forgejo";
            read = true;
            write = true;
            owner = true;
          }
        ];
      };
    };

    resources.garageKeys.harbor = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
      };
    };

    resources.garageBuckets.harbor = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-main";
        keyPermissions = [
          {
            keyRef = "harbor";
            read = true;
            write = true;
            owner = true;
          }
        ];
      };
    };

    resources.garageClusters.garage-backup = {
      metadata = {inherit namespace;};
      spec = {
        replicas = 3;
        zone = "main";

        storage = {
          data = {
            size = "300Gi";
            storageClassName = "synology-nfs";
          };
          metadata = {
            size = "20Gi";
            storageClassName = "synology-nfs";
          };
        };

        database = { engine = "sqlite"; };
        replication = { factor = 3; };

        admin = {
          enabled = true;
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

    helm.releases.garage-operator = {
      chart = charts.rajsinghtech.garage-operator;
      values = {
        replicaCount = 3;
        image.tag = "v0.0.36";
      };
    };
  };
}
