{self, ...}:
{
    flake.nixosModules.noosphere = {config, lib, pkgs, ... }:
    let
      inherit (lib) mkEnableOption mkOption types;
      cfg = config.noosphere.taghmata.rke2.server;
    in
    {
      options.noosphere.taghmata.rke2.server = {
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
          description = ''Path to the token file''
        };

cni = lib.mkOption {
      type = lib.types.enum [ "canal" "calico" "cilium" "flannel" "none" ];
      default = "canal";
      description = "CNI plugin RKE2 should deploy.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags passed to the rke2-server process.";
    };

    nodeLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "role=server" "cluster=taghmata-primus" ];
      description = ''
        Additional node labels in "key=value" form. These end up as
        Kubernetes node labels via services.rke2.nodeLabel.
      '';
    };

    nodeTaints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "node-role.kubernetes.io/control-plane=:NoSchedule" ];
      description = ''
        Optional taints in the usual "key=value:Effect" format, forwarded
        to services.rke2.nodeTaint.
      '';
    };

    manifests = lib.mkOption {
      # We just pass this straight through to services.rke2.manifests
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = ''
        RKE2 server-side manifests (forwarded to services.rke2.manifests).

        Example:

          manifests.argocd = {
            enable = true;
            source = ./manifests/argocd.yaml;
          };
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
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


    };

}
