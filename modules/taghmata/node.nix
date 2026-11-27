# What the bare-metal taghmata machines (terra, luna, sol) have in common as
# hosts, apart from their cluster roles (stc/taghmata.nix): the static address
# on the LAN NIC and the CI runner they each carry.
#
# A machine sets only what differs, in machines/<name>/configuration.nix.
{self, ...}: {
  flake.nixosModules.taghmata-node = args @ {
    config,
    lib,
    ...
  }: let
    inherit (config.networking) hostName;
    state = (args.ciNodes or self.lib.ciNodes).${hostName};
    runner = config.services.imperium.forgejoRunner;
    slot = config.services.imperium.forgejoEphemeral;
  in {
    imports = [
      self.nixosModules.forgejo-runner
      self.nixosModules.sccache
    ];

    # The address is the machine's entry in modules/cartographa/_chart.nix.
    networking.interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = self.lib.hosts.${hostName};
          prefixLength = 24;
        }
      ];
    };
    # Extend the existing networkd match; do not replace the node's primary
    # address, routes, or NIC ownership as part of the slot rollout.
    systemd.network.networks."40-enp1s0" = lib.mkIf state.slotsEnabled {
      networkConfig.IPv4DuplicateAddressDetectionTimeoutSec = "3s";
      addresses = map (address: {
        Address = "${address}/32";
        DuplicateAddressDetection = "ipv4";
      }) (builtins.filter (address: address != null) [slot.egressAddress slot.egressTrustedAddress]);
    };
    networking.defaultGateway = {
      address = self.lib.lan.gateway;
      interface = "enp1s0";
    };
    networking.nameservers = self.lib.lan.resolvers;

    # Host-step cargo builds cache into the `sccache` bucket on garage-main
    # (modules/rites/sccache.nix); wired into the runner by forgejo-runner.nix.
    services.imperium.sccache.enable = state.hostRunnerEnabled;

    services.imperium.forgejoRunner = {
      enable = state.hostRunnerEnabled;
      # Both forges: keep general CI and accept the long Machines jobs.
      labels = ["nix:host" "nix-machines:host"];
      # 1.6 TB of free disk: keep CI's store until it gets tight.
      storeCache = lib.mkIf state.hostRunnerEnabled {
        minFree = 200;
        maxFree = 400;
      };
      resources = {
        cpus = lib.mkDefault 2;
        memory = lib.mkDefault 4;
      };
    };

    # Keep the exact flag ordering and reservation set by the host runner
    # even in the intermediate generation without a runner or slot.
    services.rke2.extraFlags = lib.mkIf (!runner.enable && config.services.rke2.enable) (lib.mkAfter [
      "--kubelet-arg=system-reserved=memory=${toString runner.resources.memory}Gi"
    ]);

    users.groups.media = {
      gid = 1337;
    };

    services.dbus.enable = true;
  };
}
