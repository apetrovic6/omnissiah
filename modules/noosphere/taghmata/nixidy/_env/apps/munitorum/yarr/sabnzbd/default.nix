{
  yarr,
  config,
  cartographa,
  ...
}: let
  inherit (yarr) namespace;
  domain = config.noosphere.domain;
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

    resources.deployments.sabnzbd = {
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
              {
                name = "config";
                mountPath = "/config";
              }
              {
                name = "init-scripts";
                mountPath = "/scripts";
              }
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
              server = cartographa.hosts.manjaca;
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

    ingresses.sabnzbd-ip-root = {
      inherit namespace;
      host = "sab.${domain}";
      service = "sabnzbd";
      port = 80;
      tlsSecret = "sabnzbd-tls";
      protect = true;
      glance = {
        name = "sabnzbd";
        icon = "di:sabnzbd";
        description = "Binary newsreader";
        id = "sabnzbd";
        parent = "sabnzbd";
        category = "yarr";
      };
    };
  };
}
