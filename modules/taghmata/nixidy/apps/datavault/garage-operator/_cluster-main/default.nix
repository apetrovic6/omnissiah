{
  domain,
  lib,
  namespace,
  sccacheCiKey,
  vars,
  ...
}: let
  inherit (sccacheCiKey) generatorName importSecret;
  hasCiKey = builtins.pathExists (vars.shared generatorName generatorName);

  sccacheLifecycle = [
    {
      # sccache only writes objects it later reads back; without expiry the
      # caches only grow. Expiry counts from upload, not from the last read.
      id = "expire-after-7-days";
      status = "Enabled";
      expirationDays = 7;
      # A killed build can leave multipart uploads that expiration does not
      # cover and that still count against the quota.
      abortIncompleteMultipartUploadDays = 7;
    }
  ];
in {
  applications.garage-operator = {
    sopsSecrets = lib.optional hasCiKey generatorName;

    resources.garageClusters.garage-main = {
      metadata = {inherit namespace;};
      spec = {
        zone = "main";

        storage = {
          replicas = 3;
          data = {
            # Garage's layout capacity per node, not a real limit: local-path
            # neither enforces nor resizes a volume, and the existing nodes
            # keep their claims. Each node's /mnt/storage is a 1.8 TB NVMe
            # shared with other local-path volumes. Bounded caches total about
            # 866 GiB: ncps caps itself at 500G; sccache has 250Gi and
            # sccache-ci 150Gi. Other buckets have no quotas. Check actual
            # free space on those devices before enabling CI cache writes.
            size = "1Ti";
            storageClassName = "local-path";
          };
          metadata = {
            size = "10Gi";
            storageClassName = "local-path";
          };
          # Without fsync Garage runs SQLite with synchronous=OFF, so a power
          # cut can leave a torn DB: the 2026-11-13 outage left sol's node
          # panicking at merkle.rs:207 until db.sqlite was wiped and resynced.
          # Data blocks on local disk need the same treatment, or a block
          # file can survive the cut truncated.
          metadataFsync = true;
          dataFsync = true;
          # Consistent copies kept next to the DB (Garage keeps the newest
          # two) under metadata_dir/snapshots, so a corrupted node can copy
          # the newest one back over db.sqlite instead of a full resync.
          metadataAutoSnapshotInterval = "6h";
          # One storage node per machine, required. The nodes already sit on
          # luna, terra and sol, but only because their local-path volumes
          # happen to be pinned there. In Auto mode the operator-owned nodes
          # inherit this from the storage tier, so a rollout puts each pod
          # back on its own machine (where its volumes are) and a new node can
          # never share one. garage-backup sets the same rule per node.
          affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution = [
            {
              topologyKey = "kubernetes.io/hostname";
              labelSelector.matchLabels = {
                "garage.rajsingh.info/cluster" = "garage-main";
                "garage.rajsingh.info/tier" = "storage";
              };
            }
          ];
        };

        database = {engine = "sqlite";};
        replication = {factor = 3;};

        admin = {
          bindPort = 3903;
          adminTokenSecretRef = {
            name = "garage-main-admin-token";
            key = "admin-token";
          };
        };

        network = {
          rpcBindPort = 3901;
          service.type = "ClusterIP";
          rpcSecretRef = {
            name = "garage-main-rpc-secret";
            key = "rpc-secret";
          };
        };

        # Off for the same reason as garage-backup: Garage v2.3.0 with
        # [kubernetes_discovery] can panic at start (the operator's
        # DiscoveryCompatible=False / GarageVersionCrashesAtStart), and the
        # affinity above restarts every pod. Discovery never worked here
        # anyway: the pods' ServiceAccount has no RBAC for it, so it 403'd
        # every minute. Peering comes from the operator's connectNodes.
        discovery.kubernetes = {enabled = false;};

        layoutManagement = {
          autoApply = true;
          minNodesHealthy = 2;
        };
        layoutPolicy = "Auto";

        s3Api = {
          bindPort = 3900;
          region = "main";
          rootDomain = ".s3.main.garage.${domain}";
        };
      };
    };

    # /metrics on the admin port (3903) is the only place Garage exposes its
    # cluster health, partition quorum, resync state and per-node disk numbers.
    # Scraping it is what makes the Garage alerts in the prometheus-grafana app
    # (resources.prometheusRules.garage) evaluate at all.
    templates.garageAdminMetrics."garage-main-admin" = {
      inherit namespace;
      cluster = "garage-main";
      adminService = "garage-main-admin";
    };

    resources.services.garage-s3-api = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-main";
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

    resources.services.garage-main-admin = {
      metadata = {inherit namespace;};
      spec = {
        type = "ClusterIP";
        selector = {
          "app.kubernetes.io/name" = "garage";
          "app.kubernetes.io/instance" = "garage-main";
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

    resources.ingresses.garage-s3-api = {
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
            host = "s3.main.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
          {
            host = "*.s3.main.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-s3-api";
                  port.number = 3900;
                };
              }
            ];
          }
        ];
        tls = [
          {
            secretName = "garage-operator-s3-tls";
            hosts = ["s3.main.garage.${domain}" "*.s3.main.garage.${domain}"];
          }
        ];
      };
    };
  };

  # Buckets for consumers outside the cluster. Their key pair is generated by a
  # clan var and IMPORTED here (the operator reads access-key-id and
  # secret-access-key from the Secret the SopsSecret materialises), so the
  # machine and Garage are fed from one source and nothing is copied by hand.

  # Kaneo's uploads, on cerberus. See taghmata/reliquary/kaneo/default.nix.
  # The key owns the bucket, which is what authorises PutBucketCors: uploads
  # are presigned PUTs made by the browser.
  garage.keys.kaneo = {
    cluster = "main";
    importSecret = "kaneo-s3-import";
  };

  # Memos' attachments, on cerberus. See taghmata/reliquary/memos/default.nix.
  # Owner for the same reason as kaneo: attachment downloads are presigned
  # GETs fetched by the browser cross-origin.
  garage.keys.memos = {
    cluster = "main";
    importSecret = "memos-s3-import";
  };

  # The OpenTofu state bucket (taghmata/_tofunix). No Secret is requested: its
  # credentials are entered as a clan var (reliquary/tofunix/s3-secrets.nix).
  garage.keys.opentofu = {
    cluster = "main";
  };

  # sccache: the shared compile cache for cargo builds that run OUTSIDE the
  # Nix sandbox (the user's workstations and the Forgejo runners' host steps).
  # Nix builds stay with ncps. See modules/rites/sccache.nix.
  garage.keys.sccache = {
    cluster = "main";
    importSecret = "sccache-s3-import";

    # No owner, unlike kaneo/memos: the owner bit is what authorises
    # bucket-admin calls (PutBucketCors for their browser-facing presigned
    # traffic). sccache only ever GETs and PUTs objects. It is still written
    # into the GarageKey as `owner: false`, because the operator defaults it
    # into the list and ArgoCD compares the list whole: left out, the key
    # stays OutOfSync.
    owner = false;

    bucketSpec.sccache = {
      # 250 GiB. maxSize is an int-or-string quantity: the API server stores
      # a bare number as the string "268435456000", so a number here keeps
      # ArgoCD OutOfSync forever. A quantity string round-trips unchanged.
      quotas.maxSize = "250Gi";

      lifecycle.rules = sccacheLifecycle;
    };
  };

  # The dispatcher is the only holder. Do not reconcile either object until
  # SopsSecrets can supply the import, and never grant the workstation bucket.
  garage.keys.sccache-ci = lib.mkIf hasCiKey {
    cluster = "main";
    buckets = ["sccache-ci"];
    permissions = {
      read = true;
      write = true;
    };
    owner = false;
    inherit importSecret;
    bucketSpec.sccache-ci = {
      quotas.maxSize = "150Gi";
      lifecycle.rules = sccacheLifecycle;
    };
  };
}
