# What the bare-metal taghmata machines (terra, luna, sol) have in common as
# hosts, apart from their cluster roles (stc/taghmata.nix): the static address
# on the LAN NIC and the CI runner they each carry.
#
# A machine sets only what differs, in machines/<name>/configuration.nix.
{self, ...}: {
  flake.nixosModules.taghmata-node = {
    config,
    lib,
    ...
  }: {
    imports = [
      self.nixosModules.forgejo-runner
      self.nixosModules.sccache
    ];

    # The address is the machine's entry in modules/cartographa/_chart.nix.
    networking.interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = self.lib.hosts.${config.networking.hostName};
          prefixLength = 24;
        }
      ];
    };
    networking.defaultGateway = {
      address = self.lib.lan.gateway;
      interface = "enp1s0";
    };
    networking.nameservers = self.lib.lan.resolvers;

    # Host-step cargo builds cache into the `sccache` bucket on garage-main
    # (modules/rites/sccache.nix); wired into the runner by forgejo-runner.nix.
    services.imperium.sccache.enable = true;

    services.imperium.forgejoRunner = {
      enable = true;
      # 1.6 TB of free disk: keep CI's store until it gets tight.
      storeCache = {
        minFree = 200;
        maxFree = 400;
      };
      resources = {
        cpus = lib.mkDefault 2;
        memory = lib.mkDefault 4;
      };
    };

    users.groups.media = {
      gid = 1337;
    };

    services.dbus.enable = true;
  };
}
