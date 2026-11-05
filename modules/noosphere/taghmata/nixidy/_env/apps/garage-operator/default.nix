{
  charts,
  config,
  ...
}: let
  namespace = "garage-operator";
  domain = config.noosphere.domain;

  cluster-main = import ./cluster-main {inherit config namespace domain;};
  cluster-backup = import ./cluster-backup {inherit config namespace domain;};
in {
  imports = [cluster-main cluster-backup];
  applications.garage-operator = {
    inherit namespace;
    createNamespace = true;
    # The garageclusters CRD is ~1.1 MB. Client-side apply stores the whole
    # manifest in the last-applied-configuration annotation, capped at 256 KiB,
    # so every sync failed on that one resource and a CRD change in an operator
    # upgrade would never apply. Server-side apply keeps no such annotation.
    syncPolicy.syncOptions.serverSideApply = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-main-rpc-secret/garage-main-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-main-admin-token/garage-main-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-rpc-secret/garage-backup-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-admin-token/garage-backup-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/kaneo-s3-key/kaneo-s3-key/value)
      (builtins.readFile ../../../../../../../vars/shared/memos-s3-key/memos-s3-key/value)
    ];

    helm.releases.garage-operator = {
      chart = charts.rajsinghtech.garage-operator;
      values = {
        replicaCount = 3;
        # image.tag = "v0.0.36";
      };
    };
  };
}
