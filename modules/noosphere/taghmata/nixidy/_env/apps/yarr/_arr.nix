# One of the *arr applications: a Deployment with its config on Longhorn, a
# Service and an Ingress, storing its data in the shared pg-yarr cluster
# (./default.nix declares the database and role).
#
#   (import ./_arr.nix { name = "radarr"; port = 7878; description = "Pvr"; })
{
  name,
  # Port the application listens on.
  port,
  # Shown on the Glance dashboard.
  description,
  title ? lib.toSentenceCase name,
  # Prefix of the application's environment variables (<prefix>__POSTGRES__HOST).
  envPrefix ? lib.toUpper name,
  # Mounts the NAS media share and runs as its owner. Off for prowlarr, which
  # only manages indexers.
  mediaLibrary ? true,
  lib,
}: {
  yarr,
  config,
  cartographa,
  ...
}: let
  domain = config.noosphere.domain;
in {
  applications.${name} = {
    resources.persistentVolumeClaims."${name}-pvc" = {
      metadata = {
        inherit (yarr) namespace;

        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };

      spec = {
        accessModes = ["ReadWriteMany"];
        storageClassName = "longhorn";
        resources.requests.storage = "2Gi";
      };
    };

    resources.deployments.${name} = {
      metadata = {
        inherit (yarr) namespace;
        labels.app = "${name}";
      };

      spec = {
        selector = {
          matchLabels = {
            app = "${name}";
          };
        };
      };

      spec.template = {
        metadata.labels.app = "${name}";
        spec.volumes =
          [
            {
              name = "config";
              persistentVolumeClaim.claimName = "${name}-pvc";
            }
          ]
          ++ lib.optionals mediaLibrary [
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
            name = "${name}";

            image = "lscr.io/linuxserver/${name}:latest";
            volumeMounts =
              [
                {
                  name = "config";
                  mountPath = "/config";
                }
              ]
              ++ lib.optionals mediaLibrary [
                {
                  name = "data";
                  mountPath = "/data";
                }
              ];

            env =
              lib.optionals mediaLibrary [
                {
                  name = "PUID";
                  value = "1031";
                }
                {
                  name = "PGID";
                  value = "65537";
                }
              ]
              ++ [
                {
                  name = "${envPrefix}__POSTGRES__HOST";
                  value = "${yarr.dbClusterName}-rw";
                }
                {
                  name = "${envPrefix}__POSTGRES__PORT";
                  value = "5432";
                }
                {
                  name = "${envPrefix}__POSTGRES__USER";
                  valueFrom.secretKeyRef = {
                    name = "pg-${name}-password";
                    key = "username";
                  };
                }

                {
                  name = "${envPrefix}__POSTGRES__PASSWORD";

                  valueFrom.secretKeyRef = {
                    name = "pg-${name}-password";
                    key = "password";
                  };
                }

                {
                  name = "${envPrefix}__POSTGRES__MAINDB";
                  value = "${name}";
                }

                {
                  name = "${envPrefix}__POSTGRES__LOGDB";
                  value = "${name}-logs";
                }
                {
                  name = "${envPrefix}__SERVER__PORT";
                  value = toString port;
                }
              ];

            ports = [{containerPort = port;}];
          }
        ];
      };
    };

    resources.services.${name} = {
      metadata = {
        inherit (yarr) namespace;
      };

      spec = {
        type = "ClusterIP";
        selector = {app = "${name}";};

        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = port;
          }
        ];
      };
    };

    resources.ingresses."${name}-ip-root" = {
      metadata = {
        inherit (yarr) namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = title;
          "glance/icon" = "di:${name}";
          "glance/url" = "https://${name}.${domain}";
          "glance/description" = description;
          "glance/id" = "${name}";
          "glance/parent" = "${name}";
          "category" = "yarr";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "${name}-tls";
            hosts = ["${name}.${domain}"];
          }
        ];

        rules = [
          {
            host = "${name}.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "${name}";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    sopsSecrets = ["pg-${name}-sopssecret"];
  };
}
