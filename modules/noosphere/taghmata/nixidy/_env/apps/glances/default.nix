{config, ...}: let
  namespace = "glances";
  domain = config.noosphere.domain;
  labels = {app = "glance";};
  cfgDir = ./config;
in {
  applications.glance = {
    inherit namespace;
    createNamespace = true;

    resources.configMaps.glance-config = {
      data = {
        "glance.yml" = builtins.readFile (cfgDir + "/glance.yml");
        "home.yml" = builtins.readFile (cfgDir + "/home.yml");
      };
    };


    resources.deployments.glance = {
      metadata.labels = labels;
      spec = {
        replicas = 1;
        selector.matchLabels = labels;

        template = {
          metadata.labels = labels;
          spec = {
            volumes = [
              {
                name = "glance-config";
                configMap.name = "glance-config";
              }

              {
                name = "glance-assets";
                emptyDir.sizeLimit = "500Mi";
              }            ];
            containers = [
              {
                name = "glance";
                image = "glanceapp/glance:v0.8.4";
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                  }
                ];

                volumeMounts = [
                  {
                    name = "glance-config";
                    mountPath = "/app/config";
                  }

                  {
                    name = "glance-assets";
                    mountPath = "/app/assets";
                  }                ];
                # envFrom = [
                #   {secretRef.name = "glance-secrets";} # created by your SOPS operator
                # ];
              }
            ];
          };
        };
      };
    };

    resources.services.glance = {
      # metadata = {};

      spec = {
        type = "ClusterIP";
        selector = labels;

        ports = [
          {
            name = "http";
            protocol = "TCP";
            port = 80;
            targetPort = "http";
          }
        ];
      };
    };
  };
}
