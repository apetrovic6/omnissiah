{
  charts,
  config,
  ...
}: let
  namespace = "harbor";
  domain = config.noosphere.domain;
  db-cluster-name = "pg-harbor-rev1";
  objectStoreName = "harbor-object-store";
in {
  imports = [
    ../../../_modules/templates/garage-object-store.nix
    ../../../_modules/templates/database-template.nix
  ];

  applications.harbor = let
    storageClass = "longhorn";
  in {
    inherit namespace;
    createNamespace = true;

    resources.deployments.harbor-core.metadata.annotations."glance/hide" = "true";

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/harbor-s3-secret-key/harbor-s3-secret-key/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-admin-password-secret/harbor-admin-password-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-secret-secret-key/harbor-secret-secret-key/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-job-service-secret/harbor-job-service-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-registry-http-secret/harbor-registry-http-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-registry-credentials-secret/harbor-registry-credentials-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-redis-password-secret/harbor-redis-password-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/pg-harbor-postgres-secret/pg-harbor-postgres-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-core-secret/harbor-core-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-oidc-secret/harbor-oidc-secret/value)

      ''
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: harbor
          namespace: harbor
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt-cloudflare
            traefik.ingress.kubernetes.io/router.entrypoints: websecure
            traefik.ingress.kubernetes.io/router.tls: "true"
            glance/name: Harbor
            glance/icon: di:harbor
            glance/url: https://harbor.${domain}
            glance/description: Registry
            glance/id: harbor
            glance/parent: harbor
            category: storage
        spec:
          ingressClassName: traefik
          tls:
            - hosts:
                - harbor.noosphere.uk
              secretName: harbor-tls
          rules:
            - host: harbor.noosphere.uk
              http:
                paths:
                  - path: /api/
                    pathType: Prefix
                    backend:
                      service:
                        name: harbor-core
                        port:
                          number: 80
                  - path: /service/
                    pathType: Prefix
                    backend:
                      service:
                        name: harbor-core
                        port:
                          number: 80
                  - path: /v2/
                    pathType: Prefix
                    backend:
                      service:
                        name: harbor-core
                        port:
                          number: 80
                  - path: /chartrepo/
                    pathType: Prefix
                    backend:
                      service:
                        name: harbor-core
                        port:
                          number: 80
                  - path: /c/
                    pathType: Prefix
                    backend:
                      service:
                        name: harbor-core
                        port:
                          number: 80
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: harbor-portal
                        port:
                          number: 80
      ''
      ''
        apiVersion: cert-manager.io/v1
        kind: Issuer
        metadata:
          name: harbor-token-issuer
          namespace: harbor
        spec:
          selfSigned: {}
        ---
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: harbor-token-cert
          namespace: harbor
        spec:
          secretName: harbor-core-svc-tls
          commonName: harbor-token
          privateKey:
            algorithm: RSA
            size: 4096
            encoding: PKCS1
          issuerRef:
            name: harbor-token-issuer
            kind: Issuer
      ''
    ];
    helm.releases.harbor = {
      chart = charts.goharbor.harbor;

      values = {
        expose = {
          type = "clusterIP";
          tls = {
            enabled = false;
            # certSource = "secret";
            # secret.secretName = "harbor-tls";
          };

          clusterIP = {
            name = "harbor";
            port.httpPort = 80;

            annotations = {
              "glance/hide" = "true";
            };
          };

          ingress = {
            hosts = {
              core = "harbor.${domain}";
            };

            controller = "default";
            className = "traefik";
            annotations = {
              "glance/hide" = "true";
            };

            # route = {
            #   hosts = [
            #     {
            #       name = "harbor.${domain}";
            #       tls = true;
            #       tlsSecret = "harbor-tls";
            #     }

            #     {
            #       name = "notary.${domain}";
            #       tls = true;
            #       tlsSecret = "harbor-tls";
            #     }
            #   ];
            # };
          };
        };

        externalURL = "https://harbor.${domain}";

        persistence = {
          persistentVolumeClaim = {
            registry = {
              inherit storageClass;
              size = "20Gi";
            };

            jobservice.jobLog = {
              inherit storageClass;
              size = "1Gi";
            };

            database = {
              inherit storageClass;
              size = "5Gi";
            };

            redis = {
              inherit storageClass;
              size = "1Gi";
            };

            trivy = {
              inherit storageClass;
              size = "5Gi";
            };
          };

          imageChartStorage = {
            type = "s3";
            s3 = {
              existingSecret = "harbor-s3-secret-key";
              region = "garage";
              regionendpoint = "http://garage.garage.svc.cluster.local:3900";
              bucket = "harbor-bucket";
            };

            # Disable redirects - proxy blobs through Harbor instead of redirecting to S3
            # This allows external clients to pull images without accessing Garage directly
            disableredirect = true;
          };
        };

        existingSecretAdminPassword = "harbor-admin-password-secret";
        existingSecretAdminPasswordKey = "HARBOR_ADMIN_PASSWORD";
        existingSecretSecretKey = "harbor-secret-secret-key";

        internalTLS.enabled = false;

        core = let
          harborCoreSecret = "harbor-core-secret";
        in {
          # OIDC Configuration via CONFIG_OVERWRITE_JSON
          extraEnvVars = [
            {
              name = "CONFIG_OVERWRITE_JSON";
              valueFrom.secretKeyRef = {
                name = "harbor-oidc-config";
                key = "CONFIG_OVERWRITE_JSON";
              };
            }
          ];
          existingSecret = harborCoreSecret;
          existingXsrfSecret = harborCoreSecret;
          secretName = "harbor-core-svc-tls";
          existingXsrfSecretKey = "CSRF_KEY";
        };

        jobservice = {
          existingSecret = "harbor-job-service-secret";
          existingSecretKey = "JOBSERVICE_SECRET";
        };

        registry = {
          existingSecret = "harbor-registry-http-secret";
          existingSecretKey = "REGISTRY_HTTP_SECRET";

          credentials = {
            username = "harbor";
            existingSecret = "harbor-registry-credentials-secret";
          };
        };

        redis.external.existingSecret = "harbor-redis-password-secret";

        database = {
          type = "external";
          external = {
            host = "${db-cluster-name}-rw";
            port = "5432";
            username = "harbor";
            existingSecret = "pg-harbor-postgres-secret";
            coreDatabase = "registry";
          };
        };

        metrics = {
          enabled = true;
          serviceMonitor.enabled = true;
        };
      };
    };

    templates.garageObjectStore.${objectStoreName} = {
      inherit namespace;
      # Migrated off the failing NFS-backed `garage` cluster onto the
      # operator-managed `garage-backup` cluster (its harbor-backup bucket/key
      # are provisioned and the creds are reflected as
      # harbor-backup-s3-secret-key).
      awsDefaultRegion = "backup";
      destinationPath = "s3://harbor-backup/backups";
      endpointUrl = "http://garage-backup.garage-operator.svc.cluster.local:3900";
      S3Credentials = {
        accessKeyId = {
          name = "harbor-backup-s3-secret-key";
          key = "MINIO_ACCESS_KEY_ID";
        };
        secretAccessKey = {
          name = "harbor-backup-s3-secret-key";
          key = "MINIO_SECRET_ACCESS_KEY";
        };
      };
    };

    templates.cnpg-database-cluster.harbor-rev1 = {
      inherit namespace;
      overrideObjectStore = objectStoreName;

      cluster = {
        annotations = {
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.proj.io/sync-wave" = "-10";
          "argocd.proj.io/hook" = "PreSync";
        };

        spec = {
          storage = {
            size = "20Gi";
          };

          walStorage = {
            size = "20Gi";
          };

          plugins = [
            {
              isWALArchiver = true;
              parameters.barmanObjectName = objectStoreName;
            }
          ];

          # bootstrap.recovery.source = "origin";

          # externalClusters = [
          #   {
          #     plugin = {
          #       parameters = {
          #         barmanObjectName = objectStoreName;
          #         serverName = "pg-harbor";
          #       };
          #     };
          #   }
          # ];

          managed.roles = [
            {
              name = "harbor";
              ensure = "present";
              comment = "Harbor User";
              login = true;
              superuser = false;
              passwordSecret.name = "pg-harbor-postgres-secret";
            }
          ];
        };
      };

      databases = [
        {
          name = "registry";
          metadata.annotations = {
            "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
            "argocd.proj.io/sync-wave" = "-10";
            "argocd.proj.io/hook" = "PreSync";
          };
          spec = {
            name = "registry";
            owner = "harbor";
            cluster.name = db-cluster-name;
          };
        }
      ];

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
