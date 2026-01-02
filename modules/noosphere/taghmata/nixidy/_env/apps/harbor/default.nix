{
  charts,
  config,
  lib,
  ...
}: let
  namespace = "harbor";
  domain = config.noosphere.domain;
in {
  applications.harbor = let
    storageClass = "longhorn";
  in {
    inherit namespace;
    createNamespace = true;

    yamls = let
      harborHost = "harbor.{$domain}";
    in [
      (builtins.readFile ../../../../../../../vars/shared/harbor-s3-secret-key/harbor-s3-secret-key/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-admin-password-secret/harbor-admin-password-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-secret-secret-key/harbor-secret-secret-key/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-job-service-secret/harbor-job-service-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-registry-http-secret/harbor-registry-http-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-registry-credentials-secret/harbor-registry-credentials-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-redis-password-secret/harbor-redis-password-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/pg-harbor-postgres-secret/pg-harbor-postgres-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/harbor-core-secret/harbor-core-secret/value)
      # (builtins.readFile ../../../../../../../vars/shared/harbor-core-svc-tls/harbor-core-svc-tls/value)
      #

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

      # ''
      # apiVersion: traefik.io/v1alpha1
      # kind: IngressRoute
      # metadata:
      #   name: harbor-portal
      #   namespace: harbor
      # spec:
      #   entryPoints:
      #     - websecure
      #   routes:
      #     - match: Host(`${harborHost}`) && PathPrefix(`/`)
      #       kind: Rule
      #       services:
      #         - name: harbor-portal
      #           port: 80
      #     - match: Host(`${harborHost}`) && PathPrefix(`/c/`)
      #       kind: Rule
      #       services:
      #         - name: harbor-core
      #           port: 80
      #     - match: Host(`${harborHost}`) && PathPrefix(`/api/`)
      #       kind: Rule
      #       services:
      #         - name: harbor-core
      #           port: 80
      #     - match: Host(`${harborHost}`) && PathPrefix(`/service/`)
      #       kind: Rule
      #       services:
      #         - name: harbor-core
      #           port: 80
      #     - match: Host(`${harborHost}`) && PathPrefix(`/v2/`)
      #       kind: Rule
      #       services:
      #         - name: harbor-core
      #           port: 80
      #     - match: Host(`${harborHost}`) && PathPrefix(`/chartrepo/`)
      #       kind: Rule
      #       services:
      #         - name: harbor-core
      #           port: 80
      #   tls:
      #     secretName: harbor-tls
      # ''
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

      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: harbor-tls
          namespace: ${namespace}
        spec:
          secretName: harbor-tls
          privateKey:
            rotationPolicy: Always
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - harbor.${domain}
      ''
    ];
    # resources.ingresses.harbor = {
    #   metadata = {
    #     name = "harbor";
    #     namespace = "harbor";
    #     annotations = {
    #       "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
    #       "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
    #       "traefik.ingress.kubernetes.io/router.tls" = "true";
    #     };
    #   };

    #   spec = {
    #     ingressClassName = "traefik";

    #     tls = [{
    #       hosts = [ "harbor.noosphere.uk" ];
    #       secretName = "harbor-tls";
    #     }];

    #     rules = [{
    #       host = "harbor.noosphere.uk";
    #       http.paths = [{
    #         path = "/";
    #         pathType = "Prefix";
    #         backend.service = {
    #           name = "harbor";
    #           port.number = 80;
    #         };
    #       }];
    #     }];
    #   };
    # };

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
          };

          ingress = {
            hosts = {
              core = "harbor.${domain}";
            };

            controller = "default";
            className = "traefik";
            annotations =
              lib.mkForce {
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

        externalUrl = ["https://harbor.${domain}"];

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
          };
        };

        existingSecretAdminPassword = "harbor-admin-password-secret";
        existingSecretAdminPasswordKey = "HARBOR_ADMIN_PASSWORD";
        existingSecretSecretKey = "harbor-secret-secret-key";

        internalTLS.enabled = false;

        core = let
          harborCoreSecret = "harbor-core-secret";
        in {
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
            host = "pg-harbor-rw";
            port = "5432";
            username = "harbor";
            existingSecret = "pg-harbor-postgres-secret";
            coreDatabase = "registry";
          };
        };
      };
    };

    resources.clusters.pg-harbor = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.proj.io/sync-wave" = "-10";
          "argocd.proj.io/hook" = "PreSync";
        };
      };

      spec = {
        primaryUpdateStrategy = "unsupervised";
        instances = 2;
        storage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "20Gi";
        };

        walStorage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "20Gi";
        };

        postgresql.parameters = {
          shared_buffers = "1GB";
          max_connections = "200";
          log_statement = "ddl";
        };

        managed = {
          roles = [
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

        monitoring.enablePodMonitor = true;
      };
    };

    resources.databases.registry = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.proj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.proj.io/sync-wave" = "-10";
          "argocd.proj.io/hook" = "PreSync";
        };
      };
      spec = {
        name = "registry";
        owner = "harbor";
        cluster.name = "pg-harbor";
      };
    };
  };
}
