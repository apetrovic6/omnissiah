{charts, ...}: let
  namespace = "nfs-provisioner-system";
in {
  helm.releases.csi-driver-nfs = {
    chart = charts.kubernetes-csi.csi-driver-nfs;

    values = {
      storageClasses = [
        {
          name = "nfs-csi";
          annotations = {
            "storageclass.kubernetes.io/is-default-class" = "true";
          };

          parameters = {
            server = "192.168.1.61";
            share = "/volume1/selhosted";
          };
          reclaimPolicy = "retain";

          volumeBindingMode = "Immediate";
          allowVolumeExpansion = true;
          moundOptions = ["nfsvers=4.1"];
        }
      ];
    };
  };
}
