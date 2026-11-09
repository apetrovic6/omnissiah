# A service built by rust-app-template, run from its Harbor image.
#
# The image contract is fixed by the template's pipeline (and checked there by
# `<svc>-image-validate`): entrypoint `/bin/<bin> serve`, uid/gid 10001, the base config baked
# at /etc/<svc>, the bind host already 0.0.0.0, and nothing about the database location. So
# the only things a deployment supplies are the image tag, the port, the database URL and the
# public host:
#
#   - the database URL is CNPG's own `<cluster>-app` secret, mounted as a file and named by
#     APP__DATABASE__URL_FILE (`crates/settings` reads `_FILE` variables). The URL never enters
#     the environment, and nothing is reassembled from parts.
#   - migrations run in an init container (`<bin> migrate`, the same binary), before the server
#     starts. The service takes a Postgres advisory lock, so replicas do not race.
#   - /healthz is liveness and touches nothing; /readyz checks the database and is readiness.
#
# The CNPG cluster itself comes from database-template.nix, its backups from
# garage-object-store.nix, and the bucket/key from garage-operator's cluster-backup.
{lib, ...}: let
  inherit (lib) mkOption types optional optionalAttrs;
  uid = 10001;
in {
  templates.rust-service = {
    options = {
      namespace = mkOption {
        type = types.str;
        description = "Namespace the service runs in.";
      };

      image = mkOption {
        type = types.str;
        example = "harbor.noosphere.uk/pilot/api";
        description = "Image repository, without a tag.";
      };

      tag = mkOption {
        type = types.str;
        description = ''
          Image tag: the product's full git revision, which is what `just publish::push` tags
          every image with. A rollout is a change to this value.
        '';
      };

      binary = mkOption {
        type = types.str;
        default = "api";
        description = "The service's binary in the image (`/bin/<binary>`), used for `migrate`.";
      };

      port = mkOption {
        type = types.port;
        default = 5000;
        description = "The service's `[application] port`.";
      };

      replicas = mkOption {
        type = types.int;
        default = 1;
      };

      database = {
        cluster = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "pg-pilot";
          description = ''
            The CNPG cluster whose `<cluster>-app` secret holds the connection URL (key `uri`).
            Null for a service without a database: no URL, no migrate init container.
          '';
        };
      };

      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "pilot.noosphere.uk";
        description = "Ingress host. Null means cluster-internal only.";
      };

      glance = mkOption {
        type = types.attrsOf types.str;
        default = {};
        example = {
          name = "Pilot";
          description = "rust-app-template pilot";
          category = "dev";
        };
        description = "Glance annotations for the ingress (`glance/<key>`, plus `category`).";
      };

      env = mkOption {
        type = types.attrsOf types.str;
        default = {};
        example = {APP__REFLECTION__ENABLED = "false";};
        description = "Extra environment variables (configuration overrides, `APP__…`).";
      };

      resources = mkOption {
        type = types.attrs;
        default = {
          requests = {
            cpu = "25m";
            memory = "64Mi";
          };
          limits.memory = "256Mi";
        };
      };
    };

    output = {
      name,
      config,
      ...
    }: let
      cfg = config;
      labels = {
        "app.kubernetes.io/name" = name;
        "app.kubernetes.io/component" = "server";
      };
      hasDatabase = cfg.database.cluster != null;
      image = "${cfg.image}:${cfg.tag}";

      dbMount = {
        name = "database";
        mountPath = "/run/secrets/database";
        readOnly = true;
      };
      tmpMount = {
        name = "tmp";
        mountPath = "/tmp";
      };

      containerSecurity = {
        allowPrivilegeEscalation = false;
        readOnlyRootFilesystem = true;
        runAsNonRoot = true;
        runAsUser = uid;
        runAsGroup = uid;
        capabilities.drop = ["ALL"];
      };

      env = lib.mapAttrsToList (name: value: {inherit name value;}) (
        optionalAttrs hasDatabase {
          APP__DATABASE__URL_FILE = "${dbMount.mountPath}/uri";
        }
        // cfg.env
      );

      probe = path: {
        httpGet = {
          inherit path;
          port = "http";
        };
        periodSeconds = 10;
        timeoutSeconds = 3;
      };
    in {
      deployments.${name} = {
        metadata = {
          inherit (cfg) namespace;
          inherit labels;
        };
        spec = {
          inherit (cfg) replicas;
          selector.matchLabels = labels;
          template = {
            metadata.labels = labels;
            spec = {
              securityContext = {
                runAsNonRoot = true;
                runAsUser = uid;
                runAsGroup = uid;
                fsGroup = uid;
                seccompProfile.type = "RuntimeDefault";
              };

              initContainers = optional hasDatabase {
                name = "migrate";
                inherit image env;
                # The entrypoint is `/bin/<bin> serve`; migrate is the same binary.
                command = ["/bin/${cfg.binary}" "migrate"];
                volumeMounts = [dbMount tmpMount];
                securityContext = containerSecurity;
              };

              containers = [
                {
                  name = "server";
                  inherit image env;
                  ports = [
                    {
                      name = "http";
                      containerPort = cfg.port;
                    }
                  ];
                  # A slow first start is not a dead process: give it a minute before
                  # liveness can restart it.
                  startupProbe = probe "/healthz" // {failureThreshold = 6;};
                  livenessProbe = probe "/healthz";
                  readinessProbe = probe "/readyz";
                  volumeMounts = optional hasDatabase dbMount ++ [tmpMount];
                  securityContext = containerSecurity;
                  inherit (cfg) resources;
                }
              ];

              volumes =
                optional hasDatabase {
                  name = "database";
                  secret = {
                    secretName = "${cfg.database.cluster}-app";
                    items = [
                      {
                        key = "uri";
                        path = "uri";
                      }
                    ];
                    defaultMode = 288; # 0440
                  };
                }
                ++ [
                  {
                    name = "tmp";
                    emptyDir.sizeLimit = "64Mi";
                  }
                ];
            };
          };
        };
      };

      services.${name} = {
        metadata = {
          inherit (cfg) namespace;
          inherit labels;
        };
        spec = {
          selector = labels;
          ports = [
            {
              name = "http";
              port = 80;
              targetPort = "http";
            }
          ];
        };
      };

      ingresses = optionalAttrs (cfg.host != null) {
        ${name} = {
          metadata = {
            inherit (cfg) namespace;
            annotations =
              {
                "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
                "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
              }
              // optionalAttrs (cfg.glance != {}) (
                {
                  "glance/id" = name;
                  "glance/url" = "https://${cfg.host}";
                }
                // lib.mapAttrs' (k: v:
                  lib.nameValuePair (
                    if k == "category"
                    then "category"
                    else "glance/${k}"
                  )
                  v)
                cfg.glance
              );
          };
          spec = {
            ingressClassName = "traefik";
            rules = [
              {
                inherit (cfg) host;
                http.paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                    backend.service = {
                      inherit name;
                      port.name = "http";
                    };
                  }
                ];
              }
            ];
            tls = [
              {
                secretName = "${name}-tls";
                hosts = [cfg.host];
              }
            ];
          };
        };
      };
    };
  };
}
