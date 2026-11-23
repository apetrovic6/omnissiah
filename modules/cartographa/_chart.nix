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
    genetor = "192.168.1.109";
    cerberus = "192.168.1.105";
    servitor = "192.168.1.13";
    terra = "192.168.1.138";
    luna = "192.168.1.232";
    sol = "192.168.1.42";
    mars = "192.168.1.44";
    ryza = "192.168.1.45"; # Proxmox VM next to mars; static, reserved for BC:24:11:5A:6E:01
    stygies = "192.168.1.47"; # Hermes development VM
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
