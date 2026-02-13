{domain, namespace, ...}:

{

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

}
