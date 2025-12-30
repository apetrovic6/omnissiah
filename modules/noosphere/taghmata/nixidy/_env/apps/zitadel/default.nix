{charts, ...}: {
  applications.zitadel = let
    namespace = "zitadel";
  in {
    inherit namespace;
    createNamespace = true;
    resources.ingresses.zitadel-ip-root = {
      metadata = {
        namespace = "zitadel";

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "zitadel-tls";
            hosts = ["zitadel.noosphere.uk"];
          }
        ];

        rules = [
          {
            host = "zitadel.noosphere.uk";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "zitadel";
                  port.number = 8080;
                };
              }
            ];
          }
        ];
      };
    };

    yamls = [
      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: zitadel-tls
          namespace: zitadel
        spec:
          secretName: zitadel-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - zitadel.noosphere.uk
      ''
      ''
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
            name: master-key-secret
            namespace: zitadel
            annotations:
              argocd.argoproj.io/sync-wave: "-10"
              argocd.argoproj.io/hook: "PreSync"
        spec:
            secretTemplates:
                - name: ENC[AES256_GCM,data:ZpiqL8WCeGT+Dy2w+npIHe0=,iv:tBg1LeEfJQJ8l3BTSSdMa9q8hw0T4afRZaEB7gZSvZ0=,tag:VkihmWYHAjQJSkufOJXyeg==,type:str]
                  type: ENC[AES256_GCM,data:rU73iT4f,iv:Zbzqz1F5JIMi966GRqqutRJWnIvLa3Y8oE2G0AfbEqA=,tag:/9YCaab7KpjKk3qbrP/mYA==,type:str]
                  stringData:
                    masterkey: ENC[AES256_GCM,data:j6eh0+A/REicMbJ809O7Hj8iF/9OPEA54xdKHv/2U7g=,iv:fWjbCrQ7Fwbh4ujTUgqyZFJkoFYPfSmoXzL9tPg8zx8=,tag:galzx+oXvhnEkvrbCDBv+g==,type:str]
        sops:
            age:
                - recipient: age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g
                  enc: |
                    -----BEGIN AGE ENCRYPTED FILE-----
                    YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBiMTRRNHdITXVJb2Q4UjMx
                    MEt0YWpHMmEvNjZ3dEw1eUEwR21xZGlZNUJRCkk3TjNxMVg5TVhzZ3NQUGVrMElj
                    VVdlblhMa0VvbWdQalJKQUlJYmxtOHMKLS0tIFExeWdtTDBDbENRdkxPamx1eEpW
                    enZDbUVsTXBCbmFlQnl2Y2xLVmlzUU0KkkB8bszGIDtAXxTlQc/aFqZ3+HCxRaH7
                    26WN7HQ9uDtILt5R3CXnXRlwjBouA1kFyvQQNN/dpj6UfvqcY0aotQ==
                    -----END AGE ENCRYPTED FILE-----
            lastmodified: "2025-12-27T16:22:46Z"
            mac: ENC[AES256_GCM,data:QJ3zaGyhsu74CaaEADBFsPpdrS2RElwQ61y54pezCiGXzTcZIFqgwmlGuIC/wKkgzSoh89HFoTjQxYI9RuM4/eDzbp1N72ImbDjUdRB+3iwbHaItQU0Xz2u/JDBT0c7rC4N4ZAjQ2FNtEkafgLvr/cx73G+3+8FYK9rOz+jiens=,iv:U1q9siD+tmWe0c5D9jnFKwWM/hfik6oOukBSNaZGGwI=,tag:vGtgW+ybKnL0njJjZCp+Ow==,type:str]
            encrypted_suffix: Templates
            version: 3.11.0      ''
    ];

    helm.releases.zitadel = {
      chart = charts.zitadel.zitadel;
      includeCRDs = true;

      values = {
        env = [
          {
            name = "ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD";
            valueFrom.secretKeyRef = {
              name = "pg-zitadel-superuser";
              key = "password";
            };
          }
          {
            name = "ZITADEL_DATABASE_POSTGRES_USER_PASSWORD";
            valueFrom.secretKeyRef = {
              name = "pg-zitadel-app";
              key = "password";
            };
          }
        ];

        zitadel = {
          masterkeySecretName = "master-key-secret";
          configmapConfig = {
            ExternalDomain = "zitadel.noosphere.uk";
            ExternalSecure = true;
            ExternalPort = 443;
            TLS.enabled = false;
            Database.Postgres = {
              Host = "pg-zitadel-rw";
              Port = "5432";
              Database = "app";
              AwaitInitialConn = "5m";
              MaxOpenConns = 20;
              MaxIdleConns = 10;
              MaxConnLifetime = "30m";
              MaxConnIdleTime = "5m";
              User = {
                Username = "app";
                SSL.Mode = "disable";
              };
              Admin = {
                Username = "postgres";
                SSL.Mode = "disable";
              };
            };
            dbSslCaCrtSecret = "pg-zitadel-ca";
          };
        };

        replicaCount = 3;
        ingress = {
          enabled = false;
          className = "traefik";
        };

        login = {
          enabled = true;
          ingress = {
            enabled = true;
            className = "traefik";
          };
        };

        metrics = {
          enabled = true;
        };

        serviceAccount = {
          annotations = {
            "argocd.argoproj.io/sync-wave" = "1";
            "argocd.argoproj.io/hook" = "Sync";
          };
        };

        initJob = {
          enabled = true;
          annotations = {
            "argocd.argoproj.io/sync-wave" = "10";
            # "argocd.argoproj.io/hook" = "PostSync";
          };
          command = ""; # Means initialize Zitadel instance (without skip anything)
        };

        setupJob = {
          annotations = {
            "argocd.argoproj.io/sync-wave" = "11";
            # "argocd.argoproj.io/hook" = "PostSync";
          };
        };
      };
    };

    resources.clusters.pg-zitadel = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.argoproj.io/sync-wave" = "-10";
          "argocd.argoproj.io/hook" = "PreSync";
        };
      };

      spec = {
        imageName = "ghcr.io/cloudnative-pg/postgresql:17.7-minimal-trixie";

        # bootstrap.initdb = {
        #   database = "app";
        #   owner = "app";
        #   secret.name = "";
        # };

        enableSuperuserAccess = true;
        primaryUpdateStrategy = "unsupervised";
        instances = 2;
        storage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "2Gi";
        };

        walStorage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "2Gi";
        };

        postgresql.parameters = {
          shared_buffers = "1GB";
          max_connections = "200";
          log_statement = "ddl";
        };

        monitoring.enablePodMonitor = true;
      };
    };
  };
}
