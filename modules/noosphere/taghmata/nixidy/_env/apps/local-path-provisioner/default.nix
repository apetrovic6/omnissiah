{
  pkgs,
  lib,
  ...
}: let
  version = "v0.0.34";
  local-path-provisioner = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/rancher/local-path-provisioner/${version}/deploy/local-path-storage.yaml";
    hash = "sha256-+rjW6JM+RPivc5hgP7YxIuTqZJDwr4NUkQjWhkft2ek=";
  };

  namespace = "local-path-storage";
in {
  applications.local-path-provisioner = {
    inherit namespace;
    createNamespace = true;

    yamls = [(builtins.readFile local-path-provisioner)];

    resources.storageClasses.local-path = lib.mkForce {
      provisioner = "rancher.io/local-path";
      volumeBindingMode = "WaitForFirstConsumer";
      reclaimPolicy = "Retain";
    };

    resources.configMaps.local-path-config = {
      metadata = {inherit namespace;};
      data = {
        "config.json" = lib.mkForce (builtins.toJSON {
          nodePathMap = [
            {
              node = "DEFAULT_PATH_FOR_NON_LISTED_NODES";
              paths = ["/mnt/storage/garage"];
            }
          ];
        });
        "setup" = lib.mkForce ''
          #!/bin/sh
          set -eu
          mkdir -m 0777 -p "$VOL_DIR"
        '';
        "teardown" = lib.mkForce ''
          #!/bin/sh
          set -eu
          rm -rf "$VOL_DIR"
        '';
        "helperPod.yaml" = lib.mkForce ''
          apiVersion: v1
          kind: Pod
          metadata:
            name: helper-pod
          spec:
            priorityClassName: system-node-critical
            tolerations:
              - key: node.kubernetes.io/disk-pressure
                operator: Exists
                effect: NoSchedule
            containers:
              - name: helper-pod
                image: busybox
                imagePullPolicy: IfNotPresent
        '';
      };
    };
  };
}
