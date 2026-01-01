{config, ...}: let
  namespace = "excalidraw";
  domain = config.noosphere.domain;

  labels = {app = "excalidraw";};
in {
  applications.excalidraw = {
    inherit namespace;
    createNamespace = true;

    resources.deployments.excalidraw = {
      metadata.labels = labels;

      spec = {
        replicas = 3;
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            containers = [
              {
                name = "excalidraw";
                image = "excalidraw/excalidraw";
                ports = [
                  {
                    containerPort = 80;
                    name = "http";
                  }
                ];
              }
            ];
          };
        };
      };
    };

    resources.services.excalidraw = {
      spec = {
        selector = {
          app = labels.app;
        };

        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = "http";
          }
        ];
      };
    };
  };
}
