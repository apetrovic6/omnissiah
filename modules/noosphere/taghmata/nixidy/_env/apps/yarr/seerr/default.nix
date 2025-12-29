{...}: let
  namespace = "yarr";
in {
  applications.seerr = {
    resources.namespaces.yarr = {
      metadata = {
        name = namespace;
        labels.name = namespace;
      };
    };

    # resources.storageClasses.seerr-vol = {
    #   provisioner = "driver.longhorn.io";
    #   allowVolumeExpansion = true;
    #   parameters = {
    #     numberOfReplicas = 3;
    #     staleReplicaTimeout = 2880;
    #     fsType = "ext4";
    #   };
    # };

    resources.persistentVolumeClaims.seerr-pvc = {
      metadata = {
        inherit namespace;
      };

      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "longhorn";
        resources.requests.storage = "2Gi";
      };
    };

    resources.deployments.seerr = {
      metadata = {
        name = "seerr-deployment";
        inherit namespace;
        labels = {
          app = "seerr";
        };
      };

      spec = {
        replicas = 3;
        selector = {
          matchLabels = {
            app = "seerr";
          };
        };
        template = {
          metadata.labels.app = "seerr";
          spec.volumes = [
            {
              name = "seerr-vol";
              persistentVolumeClaim.claimName = "seerr-pvc";
            }
          ];
          spec.containers = [
            {
              name = "jellyserr";
              image = "fallenbagel/jellyseerr:2.7.3";
              volumeMounts = [
                {
                  name = "seerr-vol";
                  mountPath = "/app/config";
                }
              ];

              env = [
                {
                  name = "DB_TYPE";
                  value = "postgres";
                }

                {
                  name = "DB_HOST";
                  value = "pg-yarr-rw";
                }

                {
                  name = "DB_PORT";
                  value = "5432";
                }

                {
                  name = "DB_USER";
                  valueFrom.secretKeyRef = {
                    name = "pg-yarr-seerr";
                    key = "username";
                  };
                }

                {
                  name = "DB_PASS";
                  valueFrom.secretKeyRef = {
                    name = "pg-yarr-seerr";
                    key = "password";
                  };
                }

                {
                  name = "DB_NAME";
                  value = "seerr";
                }
              ];
              ports = [
                {
                  containerPort = 5055;
                }
              ];
            }
          ];
        };
      };
    };

    resources.services.seerr = {
      metadata = {
        inherit namespace;
      };
      spec = {
        type = "ClusterIP";
        selector = {
          app = "seerr";
        };
        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = 5055;
          }
        ];
      };
    };

    resources.ingresses.seerr-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "seerr-tls";
            hosts = ["seerr.noosphere.uk"];
          }
        ];

        rules = [
          {
            host = "seerr.noosphere.uk";
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

    yamls = [
      (builtins.readFile ../../../../../../../../vars/shared/pg-seerr-sopssecret/pg-seerr-sopssecret/value)
      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: seerr-tls
          namespace: ${namespace}
        spec:
          secretName: seerr-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - seerr.noosphere.uk
      ''
    ];

    resources.clusters.pg-yarr = {
      metadata = {
        inherit namespace;
      };

      spec = {
        primaryUpdateStrategy = "unsupervised";
        instances = 2;
        storage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "1Gi";
        };

        walStorage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "1Gi";
        };

        postgresql.parameters = {
          shared_buffers = "1GB";
          max_connections = "200";
          log_statement = "ddl";
        };

        managed = {
          roles = [
            {
              name = "seerr";
              ensure = "present";
              comment = "Seerr User";
              login = true;
              superuser = false;
              passwordSecret.name = "pg-seerr-password";
            }
          ];
        };

        monitoring.enablePodMonitor = true;
      };
    };

    resources.databases.db-seerr = {
      metadata = {
        inherit namespace;
      };
      spec = {
        name = "db-serr";
        owner = "seerr";
        cluster.name = "pg-yarr";
      };
    };
  };
}
