{
  charts,
  config,
  ...
}: let
  domain = config.noosphere.domain;
  url = "longhorn.${domain}";
in {
  applications.longhorn = let
    namespace = "longhorn-system";
  in {
    inherit namespace;
    createNamespace = true;

    resources.ingresses.longhorn-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Longhorn";
          "glance/icon" = "di:longhorn";
          "glance/url" = "https://${url}";
          "glance/description" = "Distributed network storage";
          "glance/id" = "longhorn";
          "glance/parent" = "longhorn";
          "category" = "storage";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "longhorn-tls";
            hosts = [url];
          }
        ];

        rules = [
          {
            host = url;
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "longhorn-frontend";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    helm.releases.longhorn = {
      chart = charts.longhorn.longhorn;
      values = {
        longhorn.preUpgradeChecker = {
          jobEnabled = false;
        };
        preUpgradeChecker.upgradeVersionCheck = false;
        image.longhorn = {
          instanceManager.tag = "v1.11.0-hotfix-1";
          manager.tag = "v1.11.0-hotfix-1";
        };
        persistence = {
          defaultClassReplicaCount = 2;
          reclaimPolicy = "Retain";
        };
      };
    };

    resources.storageClasses.longhorn-rec-1 = {
      provisioner = "driver.longhorn.io";
      allowVolumeExpansion = true;
      reclaimPolicy = "Delete";
      parameters = {
        numberOfReplicas = "1";
        staleReplicaTimeout = "2880"; # 48h
        fsType = "ext4";
      };
    };

    resources.storageClasses.longhorn-rec-delete-strict-local = {
      provisioner = "driver.longhorn.io";
      allowVolumeExpansion = true;
      reclaimPolicy = "Delete";
      parameters = {
        numberOfReplicas = "1";
        dataLocality = "strict-local";
        staleReplicaTimeout = "2880"; # 48h
        fsType = "ext4";
      };
    };

    resources.storageClasses.longhorn-cnpg-strict-local = {
      provisioner = "driver.longhorn.io";
      allowVolumeExpansion = true;
      reclaimPolicy = "Retain";
      parameters = {
        numberOfReplicas = "1";
        dataLocality = "strict-local";
        staleReplicaTimeout = "2880"; # 48h
        fsType = "ext4";
      };
    };
  };
}
