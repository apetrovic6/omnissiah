{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkEnableOption mkOption types;
    cfg = config.services.imperium.taghmata.rke2.agent;
  in {
    options.noosphere.taghmata.rke2.agent = {
      enable = mkEnableOption "Enable RKE2 (agent role) on this node";

      clusterName = mkOption {
        type = types.str;
        default = "";
        description = ''
          Logical name for the RKE2 cluster this agent joins.
        '';
      };

      serverAddr = mkOption {
        type = types.str;
        example = "https://rke2-server.your.lan:9345";
        description = ''
          Address of the RKE2 server to connect to, including scheme and port.
          For example: "https://10.0.0.10:9345".
        '';
      };

      tokenFile = mkOption {
        type = types.path;
        description = ''
          Path to the RKE2 cluster token file used to join this agent
          to the server. Typically provided via sops-nix, e.g.:

            tokenFile = config.sops.secrets."rke2-server-token".path;
        '';
      };

      cni = mkOption {
        type = types.enum ["canal" "calico" "cilium" "flannel" "none"];
        default = "canal";
        description = ''
          CNI plugin this node expects the cluster to use.
          Must match the servers' CNI setting.
        '';
      };

      extraFlags = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra flags passed to the rke2-agent process.";
      };

      nodeLabels = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["role=worker" "cluster=taghmata-omnissiah"];
        description = ''
          Additional node labels in "key=value" form. These end up as
          Kubernetes node labels via services.rke2.nodeLabel.
        '';
      };

      nodeTaints = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["role=infra:NoSchedule"];
        description = ''
          Optional taints in the usual "key=value:Effect" format, forwarded
          to services.rke2.nodeTaint.
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to open the common RKE2 agent ports in the firewall.

          This opens:
            - TCP 10250  (kubelet metrics, for metrics-server)
            - UDP 8472   (Flannel/Canal VXLAN)

          The agent *initiates* connections to the server (9345/6443),
          so usually you don't need to open those inbound on the agent.
        '';
      };
    };

    config = mkIf cfg.enable {
      services.rke2 = {
        enable = true;
        role = "agent";

        # Cluster join config
        serverAddr = cfg.serverAddr;
        tokenFile = cfg.tokenFile;

        # Networking / node identity
        cni = cfg.cni;
        nodeName = config.networking.hostName;

        nodeLabel = cfg.nodeLabels;
        nodeTaint = cfg.nodeTaints;

        extraFlags = cfg.extraFlags;
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [
          10250 # kubelet metrics
        ];

        allowedUDPPorts = [
          8472 # flannel/canal VXLAN
        ];
      };
    };
  };
}
