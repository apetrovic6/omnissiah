{
  domain,
  namespace,
  ...
}: {
  applications.garage-operator = {
    resources.garageClusters.garage-backup = {
      metadata = {inherit namespace;};
      spec = {
        zone = "main";

        storage = {
          replicas = 3;
          # Bulk data blocks stay on the NAS (immutable content-addressed files,
          # NFS handles these fine).
          data = {
            size = "300Gi";
            storageClassName = "synology-nfs";
          };
          # Metadata DB moved to node-local disk. SQLite/LMDB over NFS stalls on
          # fcntl locking / mmap, causing RPC ping timeouts and quorum loss.
          # Garage already replicates metadata across the 3 nodes, so local-path
          # (no extra storage-layer replication) is the right fit.
          metadata = {
            size = "20Gi";
            storageClassName = "local-path";
          };
          # Safe to fsync metadata now that it's on local SSD (crash durability).
          metadataFsync = true;
        };

        database = {engine = "sqlite";};
        replication = {factor = 3;};

        admin = {
          bindPort = 3903;
          adminTokenSecretRef = {
            name = "garage-backup-admin-token";
            key = "admin-token";
          };
        };

        network = {
          rpcBindPort = 3901;
          service.type = "ClusterIP";
          rpcSecretRef = {
            name = "garage-backup-rpc-secret";
            key = "rpc-secret";
          };
        };

        discovery.kubernetes = {enabled = true;};

        layoutManagement = {
          autoApply = true;
          minNodesHealthy = 2;
        };
        layoutPolicy = "Auto";

        s3Api = {
          bindPort = 3900;
          region = "backup";
          rootDomain = ".s3.backup.garage.${domain}";
        };
      };
    };

    resources.services.garage-backup-s3-api = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-backup";
        };
        ports = [
          {
            name = "s3";
            port = 3900;
            targetPort = 3900;
          }
        ];
      };
    };

    resources.services.garage-backup-admin = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-backup";
        };
        ports = [
          {
            name = "admin";
            port = 3903;
            targetPort = 3903;
          }
        ];
      };
    };

    resources.ingresses.garage-backup-s3-api = {
      metadata = {
        inherit namespace;
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
        };
      };
      spec = {
        ingressClassName = "traefik";
        rules = [
          {
            host = "s3.backup.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-backup-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
          {
            host = "*.s3.backup.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-backup-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
        ];
        tls = [
          {
            secretName = "garage-operator-s3-tls";
            hosts = ["s3.backup.garage.${domain}" "*.s3.backup.garage.${domain}"];
          }
        ];
      };
    };

    resources.garageKeys.pocket-id = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "pocket-id";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "pocket-id-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "pocket-id";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "pocket-id";
          };
        };
      };
    };

    resources.garageBuckets.pocket-id = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
        # keyPermissions = [
        #   {
        #     keyRef = "pocket-id";
        #     read = true;
        #     write = true;
        #     owner = true;
        #   }
        # ];
      };
    };

    # Named `forgejo-backup` rather than `forgejo`: the garage-main cluster
    # already owns a `forgejo` bucket/key pair (Gitea attachments + LFS) in
    # this same namespace, and its secret is `forgejo-s3-secret-key`.
    resources.garageKeys.forgejo-backup = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "forgejo-backup";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "forgejo-backup-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "forgejo";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "forgejo";
          };
        };
      };
    };

    resources.garageBuckets.forgejo-backup = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
      };
    };

    # Named `harbor-backup` for the same reason as `forgejo-backup`: garage-main
    # already owns a `harbor` bucket/key pair (registry blobs) in this namespace.
    resources.garageKeys.harbor-backup = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "harbor-backup";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "harbor-backup-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "harbor";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "harbor";
          };
        };
      };
    };

    resources.garageBuckets.harbor-backup = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
      };
    };

    resources.garageKeys.keycloak = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "keycloak";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "keycloak-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "keycloak";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "keycloak";
          };
        };
      };
    };

    resources.garageBuckets.keycloak = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
      };
    };

    resources.garageKeys.vikunja = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "vikunja";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "vikunja-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "vikunja";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "vikunja";
          };
        };
      };
    };

    resources.garageBuckets.vikunja = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
      };
    };

    resources.garageKeys.woodpecker = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "woodpecker";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "woodpecker-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "woodpecker";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "woodpecker";
          };
        };
      };
    };

    resources.garageBuckets.woodpecker = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
      };
    };

    resources.garageKeys.yarr = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "yarr";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "yarr-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "yarr";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "yarr";
          };
        };
      };
    };

    resources.garageBuckets.yarr = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
      };
    };
  };
}
