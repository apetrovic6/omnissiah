# Addressing and DNS.
{
  self,
  lib,
  config,
  ...
}: {
  # A static address through networkd, and no NetworkManager. stc/base.nix
  # enables NetworkManager and the hardware config enables DHCP on ens18 in
  # networkd, so this host ran two DHCP clients on one NIC: NetworkManager got
  # .105, networkd .163, and both pushed the router's DNS onto the link. This
  # host is the LAN's DNS server, so it should not depend on DHCP at all. Keep
  # .105 reserved for this MAC on the router (bc:24:11:b8:59:3a).
  networking.networkmanager.enable = lib.mkForce false;

  networking.interfaces.ens18 = {
    useDHCP = lib.mkForce false;
    ipv4.addresses = [
      {
        address = self.lib.hosts.cerberus;
        prefixLength = 24;
      }
    ];
  };

  networking.defaultGateway = {
    address = self.lib.lan.gateway;
    interface = "ens18";
  };

  # Technitium on this host is the only resolver, as on the workstations
  # (stc/workstation.nix). The router and 9.9.9.9 both give the public answer
  # for the split-horizon names: ncps.noosphere.uk resolved to the VPS, which
  # served Traefik's default certificate, and CI substitution from ncps failed.
  networking.nameservers = [self.lib.lan.dns];

  services.resolved.settings.Resolve.FallbackDNS = [];

  # The LAN's resolver, and the authority for the split-horizon zones.
  services.imperium.technitium-dns-server = {
    enable = true;
    subdomain = "technitium";
    openFirewall = true;
    port = 5380;
  };
}
