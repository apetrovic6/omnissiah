{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkEnableOption mkOption types;
    cfg = config.services.imperium.taghmata.rke2.server;
  in {
    options.services.imperium.taghmata.rke2.server = {
      enable = mkEnableOption "Enable RKE2 (Server role) on this node";

      clusterName = mkOption {
        type = types.str;
        default = "";
        description = ''
          Logical name for the cluster
        '';
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''Path to the token file'';
      };

      serverAddr = mkOption {
        type = types.str;
        default = "";
        description = "Optional RKE2 server URL for this node to join (e.g. https://first-server.lan:9345).";
      };

      cni = mkOption {
        type = types.enum ["canal" "calico" "cilium" "flannel" "none"];
        default = "calico";
        description = "CNI plugin RKE2 should deploy.";
      };

      extraFlags = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra flags passed to the rke2-server process.";
      };

      nodeLabels = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["role=server" "cluster=taghmata-primus"];
        description = ''
          Additional node labels in "key=value" form. These end up as
          Kubernetes node labels via services.rke2.nodeLabel.
        '';
      };

      nodeTaints = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["node-role.kubernetes.io/control-plane=:NoSchedule"];
        description = ''
          Optional taints in the usual "key=value:Effect" format, forwarded
          to services.rke2.nodeTaint.
        '';
      };

      manifests = mkOption {
        # We just pass this straight through to services.rke2.manifests
        type = types.attrsOf types.attrs;
        default = {};
        description = ''
          RKE2 server-side manifests (forwarded to services.rke2.manifests).

          Example:

            manifests.argocd = {
              enable = true;
              source = ./manifests/argocd.yaml;
            };
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to open the standard RKE2 ports in the firewall on this node.

          This opens:

            - 6443  (Kubernetes API)
            - 9345  (RKE2 supervisor)
            - 2379, 2380, 2381 (etcd)
            - 10250 (kubelet metrics, for metrics-server)
            - UDP 8472 (Flannel VXLAN, if using canal/flannel)

          See https://docs.rke2.io/install/requirements for details.
        '';
      };
    };

    config = mkIf cfg.enable {
      services.rke2 = {
        enable = true;
        serverAddr = cfg.serverAddr;
        role = "server";
        cni = cfg.cni;

        nodeName = config.networking.hostName;
        nodeLabel = cfg.nodeLabels;
        nodeTaint = cfg.nodeTaints;

        tokenFile = cfg.tokenFile;
        extraFlags = cfg.extraFlags;

        manifests = cfg.manifests;
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [
          6443 # Kubernetes API
          9345 # RKE2 supervisor API
          2379 # etcd client
          2380 # etcd peer
          2381 # etcd metrics
          10250 # kubelet metrics
          5473
          9098
          9099
          7946
        ];

        # Canal/flannel VXLAN (only needed for those CNIs)
        allowedUDPPorts = [
          8472
          4789
          7946
        ];
      };
    };
  };
}
