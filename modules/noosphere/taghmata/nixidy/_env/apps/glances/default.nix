{
  config,
  lib,
  pkgs,
  charts,
  ...
}: let
  namespace = "glance";
  domain = config.noosphere.domain;
  labels = {app = "glance";};
  cfgDir = ./config;

  yaml = pkgs.formats.yaml {};

  importConfig = name:
    (import ./config/${name}.nix {
      inherit domain;
      inherit lib;
    }).${
      name
    };

  mkConfigFile = fileNameToGenerate: configFile: yaml.generate fileNameToGenerate (importConfig configFile);

  # pkgs.formats.yaml emits a "%YAML 1.1" directive plus a "---" document start.
  # glance splices $include'd files into the middle of glance.yml, where a
  # directive is not a valid token ("found character that cannot start any
  # token"), so drop the header before embedding.
  readPage = file: lib.removePrefix "%YAML 1.1\n---\n" (builtins.readFile file);

  servicesFile = mkConfigFile "services.yml" "services";
  homeFile = mkConfigFile "home.yml" "home";
in {
  applications.glance = {
    inherit namespace;

    createNamespace = true;

    resources.configMaps.glance-config = {
      data = {
        "glance.yml" = builtins.readFile (cfgDir + "/glance.yml");
        "home.yml" = readPage homeFile;
        "services.yml" = readPage servicesFile;
      };
    };

    resources.ingresses.glance-ip-root = {
      metadata = {
        inherit namespace;
        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
        };
      };

      spec = {
        ingressClassName = "traefik";
        rules = [
          {
            host = "glance.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "glance";
                  port.number = 80;
                };
              }
            ];
          }
        ];

        tls = [
          {
            secretName = "glance-tls";
            hosts = ["glance.${domain}"];
          }
        ];
      };
    };

    resources.deployments.glance = {
      metadata.labels = labels;
      spec = {
        replicas = 1;
        selector.matchLabels = labels;

        template = {
          metadata.labels = labels;
          spec = {
            volumes = [
              {
                name = "glance-config";
                configMap.name = "glance-config";
              }

              {
                name = "glance-assets";
                emptyDir.sizeLimit = "500Mi";
              }
            ];
            containers = [
              {
                name = "glance";
                image = "glanceapp/glance:v0.8.6";
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                  }
                ];

                volumeMounts = [
                  {
                    name = "glance-config";
                    mountPath = "/app/config";
                  }

                  {
                    name = "glance-assets";
                    mountPath = "/app/assets";
                  }
                ];
                # envFrom = [
                #   {secretRef.name = "glance-secrets";} # created by your SOPS operator
                # ];
              }
            ];
          };
        };
      };
    };

    resources.services.glance = {
      # metadata = {};

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

  applications.glance-k8s = {
    inherit namespace;

    helm.releases.glance-k8s = {
      chart = charts.lukasdietrich.glance-k8s;
      values = {
        image = {
          repository = "ghcr.io/lukasdietrich/glance-k8s/glance-k8s";
          tag = "v0.4.3";
        };
      };
    };
  };
}
