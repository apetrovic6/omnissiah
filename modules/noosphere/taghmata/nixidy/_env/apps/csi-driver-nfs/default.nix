{charts, ...}: let
  namespace = "csi-nfs";
in {
  applications.csi-driver-nfs = {
    inherit namespace;
    createNamespace = true;

    helm.releases.csi-driver-nfs = {
      chart = charts.kubernetes-csi.csi-driver-nfs;
    };
    resources.storageClasses.synology-nfs = {
      provisioner = "nfs.csi.k8s.io";
      reclaimPolicy = "Retain"; # or "Delete"
      volumeBindingMode = "Immediate";
      allowVolumeExpansion = true;

      parameters = {
        server = "192.168.1.61";
        share = "/volume1/selhosted";
        subDir = "\${pvc.metadata.namespace}/\${pvc.metadata.name}/\${pv.metadata.name}";
        # onDelete = "delete"; # delete|retain|archive
        # mountPermissions = "0";
      };

      mountOptions = [
        "hard"
        "nfsvers=4.1"
      ];
    };
  };
}
