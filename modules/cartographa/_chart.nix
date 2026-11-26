# The chart of the network: every address that configuration refers to.
#
# Plain data, so it can be read from any layer: NixOS and Home Manager modules
# get it as `self.lib.{lan,hosts,vips}` (modules/litanies), nixidy apps as the
# `cartographa` argument, and everything else by importing ./_cartographa.nix.
#
# Raw addresses only. `*.ugalabugala.org` is a wildcard that answers for every
# name with cerberus's address, so a hostname here would silently point at the
# wrong machine.
rec {
  lan = {
    cidr = "192.168.1.0/24";
    gateway = "192.168.1.1";
    ryza-eph = "192.168.1.249"; # Dedicated CI SNAT address, not a DNS host; keep free of DHCP leases.
    # Ryza's second CI SNAT address, for trusted nix-eph runs only (HOM-32;
    # `egress.trusted` in modules/rites/_ci-slots.nix). Not a DNS host. From
    # the block .240-.247 kept for slot SNAT sources (.243 is keksic). The
    # router's DHCP pool can't be checked, so Ryza probes for a duplicate
    # before using it, and the pool should exclude the block.
    ryza-eph-trusted = "192.168.1.240";
    # The LAN's resolvers: Blocky on each, identical configs
    # (modules/rites/blocky.nix), the only resolvers that know the
    # split-horizon names. On three independent machines (cerberus and ryza
    # are VMs on different Proxmox hosts, servitor is its own board), so one
    # going down or restarting never takes DNS away. Resolvers ask the first
    # and move on to the next when it fails.
    resolvers = with hosts; [cerberus ryza servitor];
  };

  hosts = {
    # Machines of this clan, at the address they are deployed to.
    phalanx = "192.168.1.46";
    enginseer = "192.168.1.146";
    genetor = "192.168.1.227";
    cerberus = "192.168.1.105";
    servitor = "192.168.1.13";
    terra = "192.168.1.138";
    luna = "192.168.1.232";
    sol = "192.168.1.42";
    mars = "192.168.1.44";
    ryza = "192.168.1.45"; # Proxmox VM next to mars; static, reserved for BC:24:11:5A:6E:01
    # Proxmox VM on pve2; static. NOT reserved on the router (it can't), so the
    # router may lease it to another device: .47 was taken that way, hence a
    # high address, which the router hands out least.
    stygies = "192.168.1.248";
    cypramundi = "152.53.34.16";
    alfrost = "172.245.55.111";

    # Devices this flake does not manage.
    manjaca = "192.168.1.61"; # Synology NAS
    proxmox = "192.168.1.10";
    keksic = "192.168.1.243";
  };

  # MetalLB addresses on taghmata.
  vips = {
    pool = "192.168.1.251-192.168.1.253";
    traefik = "192.168.1.251";
  };
}
