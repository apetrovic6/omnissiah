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
      (builtins.readFile ../../../../../../../vars/shared/garage-operator-rpc-secret/garage-operator-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-operator-admin-token/garage-operator-admin-token/value)
    ];


    resources.garageClusters.main = {
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
            name = "garage-operator-admin-token";
            key = "admin-token";
          };
        };

        network = {
          rpcSecretRef = {
            name = "garage-operator-rpc-secret";
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
          rootDomain = ".s3.garage-main.${domain}";
        };
      };
    };

    resources.services.garage-s3-api = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "main";
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
            host = "s3.garage-main.${domain}";
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
            host = "*.s3.garage-main.${domain}";
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
            hosts = ["s3.garage-main.${domain}" "*.s3.garage-main.${domain}"];
          }
        ];
      };
    };

    helm.releases.garage-operator = {
      chart = charts.rajsinghtech.garage-operator;
      values.replicaCount = 3;
    };
  };
}
