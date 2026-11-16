{config, ...}: let
  namespace = "excalidraw";
  domain = config.noosphere.domain;
  labels = {app = "excalidraw";};
in {
  applications.excalidraw = {
    inherit namespace;
    createNamespace = true;

    resources.deployments.excalidraw = {
      metadata = {
        name = "excalidraw";
        labels = labels;
      };

      spec = {
        replicas = 1;
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
                    name = "http";
                    containerPort = 80;
                    protocol = "TCP";
                  }
                ];
              }
            ];
          };
        };
      };
    };

    ingresses.excalidraw-ip-root = {
      inherit namespace;
      host = "excalidraw.${domain}";
      service = "excalidraw";
      port = 80;
      tlsSecret = "excalidraw-tls";
      glance = {
        name = "Excalidraw";
        icon = "di:excalidraw";
        description = "Draw diagrams";
        id = "excalidraw";
        parent = "excalidraw";
        category = "utils";
      };
    };

    resources.services.excalidraw = {
      metadata = {
        name = "excalidraw";
        labels = labels;
      };

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
