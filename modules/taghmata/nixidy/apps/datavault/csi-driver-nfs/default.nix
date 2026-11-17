{self, ...}: {
  nixidy.envs.prod.apps.csi-driver-nfs = {
    charts,
    cartographa,
    ...
  }: let
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
          server = cartographa.hosts.manjaca;
          share = "/volume1/selfhosted";
          subDir = "\${pvc.metadata.namespace}/\${pvc.metadata.name}/\${pv.metadata.name}";
          # onDelete = "delete"; # delete|retain|archive
          # mountPermissions = "0";
        };

        mountOptions = [
          "proto=tcp"
          "noresvport"
          "nfsvers=4"
        ];
      };
    };
  };

  perSystem = {pkgs, ...}: let
    # nixhelm's kubernetes-csi/csi-driver-nfs pin is unusable:
    #   - its default (version 0.0.0) is the master *dev* chart, which
    #     defaults to gcr.io/k8s-staging-sig-storage/nfsplugin:canary and
    #     passes --max-snapshot-* flags the cached canary binary rejects,
    #     crashlooping csi-nfs-controller;
    #   - its 4.13.4 pin records a chartHash that doesn't match the
    #     published tarball.
    # Fetch the released chart directly instead.
    csi-driver-nfs-chart = pkgs.fetchzip {
      url = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts/v4.13.4/csi-driver-nfs-4.13.4.tgz";
      hash = "sha256-4WszOpzLQ5tMIWgLQRLfBQVgf3hBOxYqsEpDyy3/lE4=";
    };
  in {
    nixidy.charts."kubernetes-csi/csi-driver-nfs" = csi-driver-nfs-chart;
    nixidy.crds.definitions.csi-driver-nfs.chart = csi-driver-nfs-chart;
  };
}
