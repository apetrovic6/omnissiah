{ config, ... }:
let
  namespace = "searxng";
  domain = config.noosphere.domain;
  labels = {
    app = "searxng";
  };

  valkeyLabels = {
    app = "searxng-valkey";
  };
in
{
  applications.searxng = {

    resources.persistentVolumeClaims.searxng-pvc = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "longhorn-rec-1";
        resources.requests.storage = "1Gi";
      };
    };

    resources.persistentVolumeClaims.valkey-pvc = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "longhorn-rec-1";
        resources.requests.storage = "2Gi";
      };
    };

    resources.deployments.searxng = {
      metadata = {
        inherit namespace labels;
      };

      template = {
        metadata = { inherit labels; };
        spec = {
          replicas = 1;
          selector.matchLabels = labels;
          volumes = [
            {
              name = "searxng";
              persistentVolumeClaim.claimName = "searxng-pvc";
            }
          ];
          containers = [
            {
              name = "searxng";
              image = "docker.io/searxng/searxng:2026.1.24-eea189286";
              ports = [ { containerPort = 8080; } ];
              volumeMounts = [
                {
                  name = "searxng";
                  mountPath = "/etc/searxng";
                }

                {
                  name = "searxng";
                  mountPath = "/var/cache/searxng";
                }

              ];

              env = [
                {
                  name = "SEARXNG_BASE_URL";
                  value = "https://searx.${domain}";
                }

              ];

            }
          ];
        };
      };
    };

    resources.deployments.valkey = {
      medatada = { inherit namespace valkeyLabels; };
      template = {
        metadata.labels = valkeyLabels;
        spec = {
          volumes = [
            {
              name = "valkey";
              persistentVolumeClaim.claimName = "valkey-pvc";
            }
          ];

          containers = [
            {
              name = "valkey";
              image = "docker.io/valkey/valkey:9-alpine";
              command = [ "valkey-server" ];
              args = [
                "--save"
                "30"
                "1"
              ];

            }

          ];

        };
      };
    };

    resources.ingresses.searxng-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Searxng";
          "glance/icon" = "di:searxng";
          "glance/url" = "https://searx.${domain}";
          "glance/description" = "Private Meta Search Engine";
          "glance/id" = "searxng";
          "glance/parent" = "searxng";
          "category" = "utils";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "seerr-tls";
            hosts = ["seerr.${domain}"];
          }
        ];

        rules = [
          {
            host = "seerr.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "seerr";
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
