# A static address through networkd, and no NetworkManager.
#
# stc/base.nix enables NetworkManager, and the facter hardware config enables
# DHCP in networkd. Left alone, that is two DHCP clients on one NIC, the
# cerberus incident (see machines/cerberus/network.nix): two leases, and the
# router's DNS pushed onto the link so split-horizon names resolve to the VPS.
#
# The NIC is matched by the MAC tofunix pins on the VM, not by name: ryza is a
# q35 machine and mars (i440fx) is `ens18`, so the name may differ. Keep .45
# reserved for BC:24:11:5A:6E:01 on the router.
{
  self,
  lib,
  ...
}: {
  networking.networkmanager.enable = lib.mkForce false;
  networking.useDHCP = lib.mkForce false;
  networking.useNetworkd = true;

  # Sorts before any per-interface file the hardware config generates, and
  # networkd applies the first file that matches.
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:5a:6e:01";
    address = ["${self.lib.hosts.ryza}/24"];
    gateway = [self.lib.lan.gateway];
    # The LAN's Blocky resolvers, the only ones that know the split-horizon
    # names (ncps.noosphere.uk must resolve to the LAN for substitution).
    dns = self.lib.lan.resolvers;
    linkConfig.RequiredForOnline = "routable";
  };

  services.resolved.settings.Resolve.FallbackDNS = [];
}
