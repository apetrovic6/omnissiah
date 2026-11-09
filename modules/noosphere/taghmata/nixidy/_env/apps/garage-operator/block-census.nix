# Block census for both Garage clusters: counts the block files in each
# storage node's data directory, so the alerts in
# prometheus-stack/garage-alerts.nix (group garage.census) can compare the nodes.
#
# Garage cannot report this itself. After 5250 blocks and the garage-marker were
# deleted from data-garage-backup-0 on 2026-11-07, every Garage metric stayed
# green for 28 hours: the marker is only read at startup, block_rc_size counts
# metadata entries rather than files, and a missing block is only noticed when
# something reads it. See ./block-census.sh for the counting itself.
#
# The two clusters keep their data differently, hence two workloads:
# * garage-backup: all three data volumes are subdirectories of one NFS export,
#   so a single Deployment mounting that export sees every node.
# * garage-main: data is on local-path, one directory per machine under
#   /mnt/storage/garage, so a DaemonSet reads each machine's own disk.
#
# Everything is read-only: these pods sit on top of the live data of every
# Garage node, and they exist because something once deleted files there.
{...}: let
  namespace = "garage-operator";
  script = "block-census";

  # The garage-operator directory of the share that the synology-nfs
  # StorageClass provisions into (apps/csi-driver-nfs): every garage-backup
  # data PV is <this>/<pvc-name>/<pv-name>.
  nfsServer = "192.168.1.61";
  nfsPath = "/volume1/selfhosted/garage-operator";

  # local-path-provisioner's directory for this namespace's volumes
  # (apps/local-path-provisioner); entries are <pv>_<namespace>_<pvc>.
  localPath = "/mnt/storage/garage";

  podSpec = {
    cluster,
    glob,
    volume,
  }: {
    automountServiceAccountToken = false;
    securityContext = {
      # Block files are 0644 and their directories 0755 or wider on both the
      # NAS and the nodes, so nobody can read them.
      runAsNonRoot = true;
      runAsUser = 65534;
      runAsGroup = 65534;
      seccompProfile.type = "RuntimeDefault";
    };
    containers = [
      {
        name = "census";
        image = "docker.io/library/busybox:1.37.0";
        command = ["sh" "/scripts/block-census.sh"];
        env = [
          {
            name = "ROOT";
            value = "/census";
          }
          {
            name = "GLOB";
            value = glob;
          }
          {
            name = "OUT";
            value = "/www";
          }
          {
            # A garage-backup pass over NFS takes a few minutes, a garage-main
            # pass over local disk about 12 seconds; the alerts' `for` windows
            # assume 15 minutes for both.
            name = "INTERVAL";
            value = "900";
          }
        ];
        ports = [
          {
            name = "metrics";
            containerPort = 9101;
          }
        ];
        securityContext = {
          allowPrivilegeEscalation = false;
          readOnlyRootFilesystem = true;
          capabilities.drop = ["ALL"];
        };
        resources = {
          requests = {
            cpu = "10m";
            memory = "32Mi";
          };
          limits.memory = "128Mi";
        };
        volumeMounts = [
          {
            name = "census";
            mountPath = "/census";
            readOnly = true;
          }
          {
            name = "scripts";
            mountPath = "/scripts";
            readOnly = true;
          }
          {
            name = "www";
            mountPath = "/www";
          }
        ];
      }
    ];
    volumes = [
      ({name = "census";} // volume)
      {
        name = "scripts";
        configMap.name = script;
      }
      {
        name = "www";
        emptyDir.sizeLimit = "16Mi";
      }
    ];
  };

  # The observability Prometheus selects PodMonitors by
  # {release: kube-prometheus-stack}, in any namespace.
  podMonitor = {
    cluster,
    labels,
  }: {
    metadata = {
      inherit namespace;
      labels = {release = "kube-prometheus-stack";};
    };
    spec = {
      selector.matchLabels = labels;
      namespaceSelector.matchNames = [namespace];
      podMetricsEndpoints = [
        {
          port = "metrics";
          # .txt so busybox httpd answers Content-Type: text/plain, which
          # Prometheus 3 requires.
          path = "/metrics.txt";
          interval = "60s";
          relabelings = [
            # Same constant label the admin ServiceMonitors stamp: the census
            # alerts group on it, and Alertmanager's ntfy-warning route only
            # pages Garage warnings that carry it.
            {
              action = "replace";
              sourceLabels = ["__address__"];
              regex = ".*";
              replacement = cluster;
              targetLabel = "garage_cluster";
            }
            {
              action = "replace";
              sourceLabels = ["__meta_kubernetes_pod_node_name"];
              targetLabel = "node";
            }
          ];
        }
      ];
    };
  };

  backupName = "garage-backup-block-census";
  backupLabels = {
    "app.kubernetes.io/name" = "garage-block-census";
    "garage-monitoring/cluster" = "garage-backup";
  };

  mainName = "garage-main-block-census";
  mainLabels = {
    "app.kubernetes.io/name" = "garage-block-census";
    "garage-monitoring/cluster" = "garage-main";
  };
in {
  applications.garage-operator.resources = {
    configMaps.${script} = {
      metadata = {inherit namespace;};
      data."block-census.sh" = builtins.readFile ./block-census.sh;
    };

    # ---- garage-backup: one pod, the NFS export ------------------------------

    # A static PV rather than an inline `nfs:` pod volume: the in-tree NFS
    # volume shells out to the host's mount.nfs, which the NixOS nodes are not
    # guaranteed to have, while csi-driver-nfs is what already mounts every
    # Garage data volume here. Read-only on the PV, the claim and the mount;
    # Retain plus no StorageClass means deleting the claim can never reach the
    # share either.
    persistentVolumes.${backupName} = {
      metadata.labels = backupLabels;
      spec = {
        capacity.storage = "1Gi";
        accessModes = ["ReadOnlyMany"];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "";
        mountOptions = ["proto=tcp" "noresvport" "nfsvers=4"];
        csi = {
          driver = "nfs.csi.k8s.io";
          readOnly = true;
          # Must be unique per PV in the cluster; any string works for a
          # static volume, this one follows the driver's server#share layout.
          volumeHandle = "${nfsServer}#${nfsPath}#${backupName}";
          volumeAttributes = {
            server = nfsServer;
            share = nfsPath;
          };
        };
        claimRef = {
          inherit namespace;
          name = backupName;
        };
      };
    };

    persistentVolumeClaims.${backupName} = {
      metadata = {
        inherit namespace;
        labels = backupLabels;
      };
      spec = {
        accessModes = ["ReadOnlyMany"];
        storageClassName = "";
        volumeName = backupName;
        resources.requests.storage = "1Gi";
      };
    };

    deployments.${backupName} = {
      metadata = {
        inherit namespace;
        labels = backupLabels;
      };
      spec = {
        replicas = 1;
        # One scan at a time: two pods walking 155k files over NFS gain nothing.
        strategy.type = "Recreate";
        selector.matchLabels = backupLabels;
        template = {
          metadata.labels = backupLabels;
          spec = podSpec {
            cluster = "garage-backup";
            glob = "data-garage-backup*/pvc-*";
            volume.persistentVolumeClaim = {
              claimName = backupName;
              readOnly = true;
            };
          };
        };
      };
    };

    podMonitors.${backupName} = podMonitor {
      cluster = "garage-backup";
      labels = backupLabels;
    };

    # ---- garage-main: one pod per machine, the local disk ---------------------

    # No node selector: the DaemonSet lands on every untainted node, which is
    # exactly luna, terra and sol (mars is a tainted control plane with no
    # /mnt/storage). `type = Directory` makes a pod on a future node without
    # that path stay pending rather than create an empty directory on it.
    daemonSets.${mainName} = {
      metadata = {
        inherit namespace;
        labels = mainLabels;
      };
      spec = {
        selector.matchLabels = mainLabels;
        template = {
          metadata.labels = mainLabels;
          spec = podSpec {
            cluster = "garage-main";
            # Matches only the live set's naming: the pre-operator
            # data-main-* directories still on these disks are skipped here,
            # and any other leftover is dropped by the alerts' Bound-PV join.
            glob = "*_data-garage-main-*";
            volume.hostPath = {
              path = localPath;
              type = "Directory";
            };
          };
        };
      };
    };

    podMonitors.${mainName} = podMonitor {
      cluster = "garage-main";
      labels = mainLabels;
    };
  };
}
