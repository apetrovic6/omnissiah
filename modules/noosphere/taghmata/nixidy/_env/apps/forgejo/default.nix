{
  config,
  charts,
  ...
}: let
  name = "forgejo";
  domain = config.noosphere.domain;
  url = "forge.${domain}";
  namespace = "${name}";
  db-cluster-name = "pg-${name}";
  objectStoreName = "${name}-object-store";
  forgejo-admin-secret = "forgejo-admin-secret";
  forgejo-keycloak-oauth-secret = "forgejo-keycloak-oauth-secret";
in {
  imports = [
    ../../../_modules/templates/garage-object-store.nix
    ../../../_modules/templates/database-template.nix
  ];

  applications.${name} = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/${forgejo-admin-secret}/${forgejo-admin-secret}/value)
      (builtins.readFile ../../../../../../../vars/shared/${forgejo-keycloak-oauth-secret}/${forgejo-keycloak-oauth-secret}/value)
    ];

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
    };
    # resources.ingressRouteTCPs."forgejo-ssh" = {
    #   kind = "IngressRouteTCP";
    #   metadata.namespace = namespace;
    #   spec = {
    #     entryPoints = ["ssh"];
    #     routes = [
    #       {
    #         match = "HostSNI(`forge.noosphere.uk)";
    #         services = [
    #           {
    #             name = "forgejo-ssh";
    #             port = 22;
    #           }
    #         ];
    #       }
    #     ];
    #   };
    # };

    helm.releases.${name} = {
      chart = charts.forgejo-helm.forgejo;
      values = {
        replicaCount = 1; # TODO: Implement Redis / Valkey for high availability
        containerSecurityContext = {
          allowPrivilegeEscalation = false;
          capabilities = {
            drop = ["all"];
            #   # Add the SYS_CHROOT capability for root and rootless images if you intend to
            #   # run pods on nodes that use the container runtime cri-o. Otherwise, you will
            #   # get an error message from the SSH server that it is not possible to read from
            #   # the repository.
            #   # https://gitea.com/gitea/helm-chart/issues/161
            add = ["SYS_CHROOT"];
          };
          privileged = false;
          readOnlyRootFilesystem = true;
          runAsGroup = 1000;
          runAsNonRoot = true;
          runAsUser = 1000;
        };

        ingress = {
          enabled = true;
          className = "traefik";
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
            "glance/name" = "Forgejo";
            "glance/icon" = "di:forgejo";
            "glance/url" = "https://${url}";
            "glance/description" = "Git Forge";
            "glance/id" = name;
            "glance/parent" = name;
            "category" = "gitops";
          };
          hosts = [
            {
              host = url;
              paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                  port = "http";
                }
              ];
            }
          ];

          tls = [
            {
              secretName = "forgejo-tls";
              hosts = [url];
            }
          ];
        };

        persistence = {
          enabled = true;
          storageClass = "longhorn";
          accessModes = ["ReadWriteMany"];
        };

        service.ssh = {
          type = "LoadBalancer";
          port = 22;
          annotations = {
            # sharing key (same key on both Services you want to share an IP)
            "metallb.io/allow-shared-ip" = "noosphere";
            "metallb.io/loadBalancerIPs" = "192.168.1.240";
          };
        };

        gitea = {
          additionalConfigSources = [];

          additionalConfigFromEnvs = [
            {
              name = "FORGEJO__database__DB_TYPE";
              value = "postgres";
            }

            {
              name = "FORGEJO__database__HOST";
              value = "${db-cluster-name}-rw:5432";
            }

            {
              name = "FORGEJO__database__NAME";
              valueFrom.secretKeyRef = {
                name = "${db-cluster-name}-app";
                key = "dbname";
              };
            }

            {
              name = "FORGEJO__database__USER";
              valueFrom.secretKeyRef = {
                name = "${db-cluster-name}-app";
                key = "username";
              };
            }

            {
              name = "FORGEJO__database__PASSWD";
              valueFrom.secretKeyRef = {
                name = "${db-cluster-name}-app";
                key = "password";
              };
            }
          ];

          config = {
            APP_NAME = "Imperial Forge";
            database = {
              DB_TYPE = "postgres";
              HOST = "${db-cluster-name}-rw";
            };

            oauth2 = {
              # Prevent "token was already used" errors when multiple
              # concurrent requests try to refresh the same token
              INVALIDATE_REFRESH_TOKENS = false;
            };

            openid = {};
          };

          admin.existingSecret = forgejo-admin-secret;

          metrics = {
            enabled = true;
            serviceMonitor.enabled = true;
          };

          oauth = [
            {
              name = "Keycloak";
              existingSecret = forgejo-keycloak-oauth-secret;
              autoDiscoverUrl = config.noosphere.sso.wellKnownUrl;
              provider = "openidConnect";
            }
          ];
        };
      };
    };

    templates.cnpg-database-cluster.forgejo = {
      inherit namespace;
      overrideObjectStore = objectStoreName;

      cluster = {
        annotations = {
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.proj.io/sync-hook" = "PreSync";
        };

        spec = {
          plugins = [
            {
              isWALArchiver = true;
              parameters.barmanObjectName = objectStoreName;
            }
          ];
        };
      };

      # Forgejo uses the default database created with the cluster
      databases = [];

      backups = {
        scheduledBackups = [
          {
            metadata.namespace = namespace;
            spec = {
              schedule = "0 2 0 * * *"; # Backup at 2AM every night
              backupOwnerReference = "self";
              immediate = true;
            };
          }
        ];

        onDemandBackups = [
          {
            spec = {};
          }
        ];
      };
    };
  };
}
