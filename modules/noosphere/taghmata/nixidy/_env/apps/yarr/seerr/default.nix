{...}: {
  applications.seerr = {
    resources.namespaces.yarr = {
      metadata = {
        name = "yarr";
        labels.name = "yarr";
      };
    };
    resources.deployments.seerr = {
      metadata = {
        name = "seerr-deployment";
        namespace = "yarr";
        labels = {
          app = "seerr";
        };
      };

      spec = {
        replicas = 3;
        selector = {
          matchLabels = {
            app = "seerr";
          };
        };
        template = {
          metadata.labels.app = "seerr";
          spec.containers = [
            {
              name = "jellyserr";
              image = "fallenbagel/jellyseerr:2.7.3";
              ports = [
                {
                  containerPort = 5055;
                }
              ];
            }
          ];
        };
      };
    };

    resources.services.seerr = {
      metadata = {
        namespace = "yarr";
      };
      spec = {
        type = "ClusterIP";
        selector = {
          name = "seerr";
        };
        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 5055;
          }
        ];
      };
    };
  };
}
