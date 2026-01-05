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


    resources.ingresses.excalidraw-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Excalidraw";
          "glance/icon" = "di:excalidraw";
          "glance/url" = "https://excalidraw.${domain}";
          "glance/description" = "Draw diagrams";
          "glance/id" = "excalidraw";
          "glance/parent" = "excalidraw";
          "category" = "utils";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "excalidraw-tls";
            hosts = ["excalidraw.${domain}"];
          }
        ];

        rules = [
          {
            host = "excalidraw.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "excalidraw";
                  port.number = 80;
                };
              }
            ];
          }
        ];
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
