{charts, ...}: {
  applications.longhorn = let
    namespace = "longhorn-system";
  in {
    inherit namespace;
    createNamespace = true;

    helm.releases.longhorn = {
      chart = charts.longhorn.longhorn;
      values = {
        longhorn = {
          preUpgradeChecker.jobEnabled = false;
          persistance.defaultClassReplicaCount = 2;
        };
      };
    };

    resources.storageClasses.longhorn-cnpg-strict-local = {
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
  };}
