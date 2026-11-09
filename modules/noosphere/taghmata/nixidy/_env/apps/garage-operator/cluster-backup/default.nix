{
  domain,
  namespace,
  ...
}: let
  # One garage-backup storage pod per machine, enforced by the scheduler.
  #
  # The operator wires spec.affinity straight into the pod template
  # (garagenode_controller.go:1251-1253 -> PodSpecConfig.Affinity ->
  # buildGaragePodSpec, helpers.go:1571). It replaces the storage tier
  # template's affinity wholesale; garage-backup sets none, so nothing is being
  # overridden.
  #
  # required, not preferred: preferred is a hint, and a hint is what we already
  # had. The spread we are fixing happened precisely because nothing prevented a
  # second storage pod from landing on luna when its PVC was provisioned there.
  #
  # The selector matches only this cluster's storage pods - garage-main runs its
  # own three pods on the same three machines and is deliberately out of scope.
  #
  # Safe during a rollout: each pod's local-path metadata PV already pins it to
  # one host, and the operator replaces pods one at a time. When storage-0-0 is
  # deleted, terra and sol are excluded by anti-affinity and luna - the only host
  # its PV can bind to - is free because its own pod is gone.
  storageAntiAffinity = {
    podAntiAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = [
        {
          topologyKey = "kubernetes.io/hostname";
          labelSelector = {
            matchLabels = {
              "garage.rajsingh.info/cluster" = "garage-backup";
              "garage.rajsingh.info/tier" = "storage";
            };
          };
        }
      ];
    };
  };
in {
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

        # Garage v2.3.0 + [kubernetes_discovery] is the operator's known
        # rustls-panic combination (status condition DiscoveryCompatible=False /
        # GarageVersionCrashesAtStart; upstream #1416, #1526, #1532, #1536, fixed
        # in Garage v2.4.1). Discovery is also dead weight here: it is a
        # garagenodes.deuxfleurs.fr CR round-trip, and the garage pods' ServiceAccount
        # has no RBAC for it, so the 60s publish fails with 403 and the discover
        # half never runs (Garage only runs it in its bootstrap branch). Peering
        # comes from bootstrap_peers + each node's on-disk peer_list cache + the
        # operator's periodic bootstrapCluster/connectNodes nudge, which runs for
        # storage topologies in Auto and Manual alike.
        discovery.kubernetes = {enabled = false;};

        layoutManagement = {
          autoApply = true;
          minNodesHealthy = 2;
        };
        # Manual: we own the storage GarageNodes. One-way (the webhook rejects
        # Manual -> Auto). Setting this ejects the three operator-owned nodes by
        # dropping their GarageCluster ownerRef and app.kubernetes.io/managed-by
        # label - no pod, PVC or layout change. It is required because Auto mode
        # can only scale down the highest ordinal, so "keep slot 3, retire the
        # luna duplicate" is not expressible there.
        layoutPolicy = "Manual";

        s3Api = {
          bindPort = 3900;
          region = "backup";
          rootDomain = ".s3.backup.garage.${domain}";
        };
      };
    };

    # The two surviving operator-era nodes, adopted into git.
    #
    # These specs mirror the live objects field-for-field so that ArgoCD adoption
    # is a no-op: with no last-applied annotation on a live object kubectl apply
    # falls back to a two-way merge, which replaces every top-level key it is
    # given and leaves the rest alone - so anything we declare must already match
    # what is there. spec.storage.*.existingClaim in particular must be declared:
    # dropping it would let the operator reach for fresh claims.
    #
    # spec.nodeId is stable for these two (the operator never writes spec.nodeId,
    # it records the discovered ID in status.nodeId) and the webhook treats it as
    # immutable, so mirroring it is safe and keeps the diff empty.
    #
    # tags is the one field deliberately NOT mirrored. The live objects carry
    # cluster:garage-backup/garage-operator and tier:storage, which the operator
    # wrote when Auto mode created them; those prefixes are reserved
    # (operatorManagedNodeLayoutTagPrefixes) and are rejected in user specs. The
    # operator composes the layout role itself - desiredNodeRoleTags discards
    # reserved values from spec.tags and re-adds its own - and reports the result
    # in status.tags, so stripping them from the CR changes nothing in Garage.
    resources.garageNodes."garage-backup-storage-0" = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
        zone = "main";
        capacity = "300Gi";
        gateway = false;
        nodeId = "89ecc25cb9e15ebbba8989a48cb0a213f2476c21d9ba87b72de02879cd277714";
        affinity = storageAntiAffinity;
        tags = ["garage-backup-storage-0-0"];
        storage = {
          metadata.existingClaim = "metadata-garage-backup-0";
          data.existingClaim = "data-garage-backup-0";
        };
      };
    };

    resources.garageNodes."garage-backup-storage-1" = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
        zone = "main";
        capacity = "300Gi";
        gateway = false;
        nodeId = "0b856d9cc98c64a3258df6d4e019377fdc3fde302f6f3c875827f0f4a5a82b3b";
        affinity = storageAntiAffinity;
        tags = ["garage-backup-storage-1-0"];
        storage = {
          metadata.existingClaim = "metadata-garage-backup-1";
          data.existingClaim = "data-garage-backup-1";
        };
      };
    };

    # Third storage node, pinned to sol, so the three storage nodes sit one per
    # machine (luna / terra / sol) instead of two on luna. Fresh identity: the
    # operator discovers the Garage node ID from the pod and records it in
    # status.nodeId - it never writes spec.nodeId for user-created nodes.
    # Fresh PVCs on purpose: reusing garage-backup-storage-2's claims for a new
    # identity is rejected by the operator and is not a supported Garage state.
    #
    # Push this only after commit 1a has converged: StorageRolloutReady=True
    # (reason Converged) and status.storageRollout null. The GarageNode webhook
    # refuses a create while the parent cluster is mid-rollout.
    resources.garageNodes."garage-backup-storage-3" = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";
        zone = "main";
        capacity = "300Gi";
        nodeSelector = {"kubernetes.io/hostname" = "sol";};
        affinity = storageAntiAffinity;
        # Pod-name tag only: the operator adds its own ownership/tier tags to the
        # layout role by itself (cluster:<name>/<ns>, cluster-uid, tier:storage,
        # rpc-address), and the webhook rejects user tags carrying those reserved
        # prefixes. This mirrors the debug tag Auto mode put on the other two.
        tags = ["garage-backup-storage-3-0"];
        storage = {
          metadata = {
            size = "20Gi";
            storageClassName = "local-path";
          };
          data = {
            size = "300Gi";
            storageClassName = "synology-nfs";
          };
        };
      };
    };

    # Same as garage-main: garage-backup holds every CNPG backup and WAL archive,
    # and today nothing watches it. Its admin port is the only source of the
    # cluster/partition/resync/disk gauges the rules in the prometheus-grafana app
    # alert on.
    templates.garageAdminMetrics."garage-backup-admin" = {
      inherit namespace;
      cluster = "garage-backup";
      adminService = "garage-backup-admin";
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

    # Named `ncps-backup` for the same reason as `forgejo-backup` below:
    # garage-main already owns an `ncps` bucket/key pair (the binary cache's
    # own NAR storage) in this namespace. This one only holds CNPG backups and
    # WAL for pg-ncps-rev1.
    resources.garageKeys.ncps-backup = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "ncps-backup";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "ncps-backup-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "ncps";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "ncps";
          };
        };
      };
    };

    resources.garageBuckets.ncps-backup = {
      metadata = {inherit namespace;};
      spec.clusterRef.name = "garage-backup";
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

    resources.garageKeys.pilot = {
      metadata = {inherit namespace;};
      spec = {
        clusterRef.name = "garage-backup";

        bucketPermissions = [
          {
            bucketRef.name = "pilot";
            read = true;
            write = true;
            owner = true;
          }
        ];

        secretTemplate = {
          name = "pilot-s3-secret-key";
          accessKeyIdKey = "MINIO_ACCESS_KEY_ID";
          secretAccessKeyKey = "MINIO_SECRET_ACCESS_KEY";
          annotations = {
            "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "pilot";
            "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
            "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = "pilot";
          };
        };
      };
    };

    resources.garageBuckets.pilot = {
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
