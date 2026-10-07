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
    options.services.imperium.taghmata.rke2.agent = {
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

      # NOTE: there is deliberately no `cni` option here.
      #
      # `--cni` is a server-only flag. An agent takes its CNI from the cluster
      # it joins, and passing the flag anyway is not ignored -- rke2 exits
      # immediately on the unknown flag:
      #
      #   $ rke2 agent --cni=calico
      #   Incorrect Usage: flag provided but not defined: -cni
      #
      # nixpkgs says the same in its own module (services/cluster/rancher/rke2.nix):
      # for an agent, `agentToken`, `agentTokenFile`, `disable` and `cni`
      # should not be set. Leave services.rke2.cni unset (null) on agents.

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

      nodeIP = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "192.168.1.13";
        description = ''
          Address to advertise as this node's InternalIP. Worth setting on any
          node that has more than one address on its primary interface --
          kubelet otherwise picks one on its own, and the cluster caches the
          choice.
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to open the common RKE2 agent ports in the firewall.

          The agent *initiates* its connections to the server (9345/6443), so
          those do not need opening inbound here. What does:

            - TCP 10250        kubelet (metrics-server, `kubectl logs/exec`)
            - TCP 9098, 9099   Calico Typha and Felix metrics
            - TCP/UDP 7946     MetalLB speaker memberlist
            - UDP 4789         Calico VXLAN
            - UDP 8472         Flannel/Canal VXLAN
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
        nodeName = config.networking.hostName;
        nodeIP = cfg.nodeIP;

        nodeLabel = cfg.nodeLabels;
        nodeTaint = cfg.nodeTaints;

        extraFlags = cfg.extraFlags;
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [
          10250 # kubelet metrics
          9098 # calico typha metrics
          9099 # calico felix metrics
          7946 # metallb speaker memberlist
        ];

        allowedUDPPorts = [
          # 4789 is the one that actually matters for this cluster: the
          # default-ipv4-ippool runs vxlanMode=Always. Leaving it closed
          # black-holes pod-to-pod traffic to this node, which reads as a CNI
          # fault rather than a firewall one.
          4789 # calico VXLAN
          8472 # flannel/canal VXLAN
          7946 # metallb speaker memberlist
        ];
      };
    };
  };
}
