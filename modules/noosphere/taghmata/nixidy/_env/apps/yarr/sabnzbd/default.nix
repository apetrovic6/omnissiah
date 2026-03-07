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
        storageClassName = "longhorn";
        resources.requests.storage = "2Gi";
      };
    };

    resources.configMaps.sabnzbd-init = {
      metadata = {inherit namespace;};
      data."init-config.sh" = ''
        #!/bin/sh
        INI=/config/sabnzbd.ini
        if [ ! -f "$INI" ]; then
          echo "sabnzbd.ini not found, skipping patch"
          exit 0
        fi
        if grep -q '^host_whitelist' "$INI"; then
          sed -i "s|^host_whitelist.*|host_whitelist = sab.${domain}|" "$INI"
        else
          sed -i '/^\[misc\]/a host_whitelist = sab.${domain}' "$INI"
        fi
        echo "host_whitelist patched"
      '';
    };

    resources.deployments.sabnzbd= {
      metadata = {
        inherit namespace labels;
      };

      spec = {selector.matchLabels = labels;};

      spec.template = {
        metadata = {inherit labels;};
        spec.initContainers = [
          {
            name = "init-config";
            image = "busybox:latest";
            command = ["sh" "/scripts/init-config.sh"];
            volumeMounts = [
              {name = "config"; mountPath = "/config";}
              {name = "init-scripts"; mountPath = "/scripts";}
            ];
          }
        ];

        spec.volumes = [
          {
            name = "config";
            persistentVolumeClaim.claimName = "sabnzbd-config";
          }
          {
            name = "init-scripts";
            configMap = {
              name = "sabnzbd-init";
              defaultMode = 493; # 0755
            };
          }
          {
            name = "data";
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
                name = "data";
                mountPath = "/data";
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

    resources.ingresses.sabnzbd-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "sabnzbd";
          "glance/icon" = "di:sabnzbd";
          "glance/url" = "https://sab.${domain}";
          "glance/description" = "Binary newsreader";
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
