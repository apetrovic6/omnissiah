{
  charts,
  config,
  ...
}: let
  namespace = "garage-operator";
  domain = config.noosphere.domain;
in {
  applications.garage-operator = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-main-rpc-secret/garage-main-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-main-admin-token/garage-main-admin-token/value)
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


    resources.garageClusters.garage-main = {
      metadata = {inherit namespace;};
      spec = {
        replicas = 3;
        zone = "main";

        storage = {
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
          enabled = true;
          adminTokenSecretRef = {
            name = "garage-main-admin-token";
            key = "admin-token";
          };
        };

        network = {
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

    resources.services.garage-main-admin= {
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

    helm.releases.garage-operator = {
      chart = charts.rajsinghtech.garage-operator;
      values = {
        replicaCount = 3;
        image.tag = "v0.0.36";
      };
    };
  };
}
