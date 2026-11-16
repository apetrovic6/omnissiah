{
  charts,
  config,
  cartographa,
  ...
}: let
  domain = config.noosphere.domain;
  url = "longhorn.${domain}";
in {
  applications.longhorn = let
    namespace = "longhorn-system";
  in {
    inherit namespace;
    createNamespace = true;

    ingresses.longhorn-ip-root = {
      inherit namespace;
      host = url;
      service = "longhorn-frontend";
      port = 80;
      tlsSecret = "longhorn-tls";
      glance = {
        name = "Longhorn";
        icon = "di:longhorn";
        url = "https://${url}";
        description = "Distributed network storage";
        id = "longhorn";
        parent = "longhorn";
        category = "storage";
      };
    };

    helm.releases.longhorn = {
      chart = charts.longhorn.longhorn;
      values = {
        longhorn.preUpgradeChecker = {
          jobEnabled = false;
        };
        preUpgradeChecker.upgradeVersionCheck = false;
        image.longhorn = {
          # instanceManager.tag = "v1.11.0-hotfix-1";
          # manager.tag = "v1.11.0-hotfix-1";
        };
        persistence = {
          defaultClassReplicaCount = 2;
          reclaimPolicy = "Retain";
        };
        defaultSettings = {
          storageNetwork = "longhorn-system/longhorn-storage-network";
        };
      };
    };

    yamls = [
      ''
        apiVersion: k8s.cni.cncf.io/v1
        kind: NetworkAttachmentDefinition
        metadata:
          name: longhorn-storage-network
          namespace: longhorn-system
        spec:
          config: |-
            {
              "cniVersion": "0.3.1",
              "type": "macvlan",
              "master": "enp2s0",
              "mode": "bridge",
              "ipam": {
                "type": "whereabouts",
                "range": "10.0.100.0/24"
              }
            }
      ''
      ''
        apiVersion: longhorn.io/v1beta2
        kind: BackupTarget
        metadata:
          name: default
          namespace: longhorn-system
        spec:
          backupTargetURL: "nfs://${cartographa.hosts.manjaca}:/volume1/longhorn_backup"
          credentialSecret: ""
          # Kubernetes canonicalises metav1.Duration on write, so "300s" comes
          # back as "5m0s" and Argo CD reports a diff it can never reconcile.
          # Declare the canonical form.
          pollInterval: "5m0s"
      ''
    ];

    # Daily snapshot at 1 AM, keep 7
    resources.longhornRecurringJobs.snapshot-daily = {
      metadata.namespace = namespace;
      spec = {
        task = "snapshot";
        cron = "0 1 * * *";
        retain = 7;
        concurrency = 1;
        groups = ["default"];
      };
    };

    # Weekly filesystem trim on Sunday at 3 AM to reclaim freed space
    resources.longhornRecurringJobs.trim-weekly = {
      metadata.namespace = namespace;
      spec = {
        task = "filesystem-trim";
        cron = "0 3 * * 0";
        retain = 0;
        concurrency = 1;
        groups = ["default"];
      };
    };

    # Daily backup to NFS at 2 AM, keep 7
    resources.longhornRecurringJobs.backup-daily = {
      metadata.namespace = namespace;
      spec = {
        task = "backup";
        cron = "0 2 * * *";
        retain = 7;
        concurrency = 1;
        groups = ["default"];
      };
    };

    resources.storageClasses.longhorn-rec-1 = {
      provisioner = "driver.longhorn.io";
      allowVolumeExpansion = true;
      reclaimPolicy = "Delete";
      parameters = {
        numberOfReplicas = "1";
        staleReplicaTimeout = "2880"; # 48h
        fsType = "ext4";
      };
    };

    resources.storageClasses.longhorn-rec-delete-strict-local = {
      provisioner = "driver.longhorn.io";
      allowVolumeExpansion = true;
      reclaimPolicy = "Delete";
      parameters = {
        numberOfReplicas = "1";
        dataLocality = "strict-local";
        staleReplicaTimeout = "2880"; # 48h
        fsType = "ext4";
      };
    };

    resources.storageClasses.longhorn-cnpg-strict-local = {
      provisioner = "driver.longhorn.io";
      allowVolumeExpansion = true;
      reclaimPolicy = "Retain";
      parameters = {
        numberOfReplicas = "1";
        dataLocality = "strict-local";
        staleReplicaTimeout = "2880"; # 48h
        fsType = "ext4";
      };
    };
  };
}
