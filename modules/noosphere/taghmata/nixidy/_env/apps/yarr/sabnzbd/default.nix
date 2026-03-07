{
  domain,
  namespace,
  ...
}: let
  labels = {app = "sabnzbd";};
in {
  applications.sabnzbd = {
    resources.persistentVolumeClaims.sabnzbd-config = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };

      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClass = "longhorn";
        resources.requests.storage = "2Gi";
      };
    };

    resources.deployments.radarr = {
      metadata = {
        inherit namespace labels;
      };

      spec = {selector.matchLabels = labels;};

      spec.template = {
        metadata = {inherit labels;};
        spec.volumes = [
          {
            name = "config";
            persistentVolumeClaim.claimName = "sabnzbd-config";
          }
          {
            name = "incomplete";
            nfs = {
              server = "192.168.1.61";
              path = "/volume1/data/";
            };
          }

          {
            name = "complete";
            nfs = {
              server = "192.168.1.61";
              path = "/volume1/data/";
            };
          }
        ];

        spec.containers = [
          {
            name = "sabnzbd";
            image = "lscr.io/linuxserver/sabnzbd:latest";
            volumeMounts = [
              {
                name = "config";
                mountPath = "/config";
              }

              {
                name = "incomplete";
                mountPath = "/incomplete-downloads";
              }

              {
                name = "complete";
                mountPath = "/downloads";
              }
            ];

            env = [
              {
                name = "PUID";
                value = "1031";
              }
              {
                name = "PGID";
                value = "65537";
              }
            ];

            ports = [{containerPort = 8080;}];
          }
        ];
      };
    };

    resources.services.sabnzbd = {
      metadata = {
        inherit namespace;
      };

      spec = {
        type = "ClusterIP";
        selector = labels;
        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 8080;
          }
        ];
      };
    };

    resources.ingress.sabnzbd-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "sabnzbd";
          "glance/icon" = "di:sabnzbd";
          "glance/url" = "https://sab.${domain}";
          "glance/description" = "Pvr";
          "glance/id" = "sabnzbd";
          "glance/parent" = "sabnzbd";
          "category" = "yarr";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "sabnzbd-tls";
            hosts = ["sab.${domain}"];
          }
        ];

        rules = [
          {
            host = "sab.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "sabnzbd";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };
  };
}
