# ryza: the general-purpose VM on the Proxmox host at 192.168.1.11, next to
# mars. The VM itself is declared in tofunix
# (modules/taghmata/_tofunix/manufactorum.nix); this is what runs inside it.
# Meant for CI runners for both forges and for the always-on agent.
{self, ...}: {
  imports = [
    self.nixosModules.blocky
    ./network.nix
    ./forgejo-runner.nix
    ./hermes.nix
  ];

  # tofunix enables the agent on the VM; Proxmox reads IPs and shuts the guest
  # down cleanly through it.
  services.qemuGuest.enable = true;

  nix.settings = {
    # CI fills the store quickly. The base tag's daily gc only drops paths
    # older than 10 days, so also collect mid-build once free space drops below
    # min-free, until max-free (as cerberus does). 200 GiB disk.
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 50 * 1024 * 1024 * 1024;
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Blocky, in parallel with Technitium for now: port 5335 (53 is Technitium's
  # on cerberus; 5353 is mDNS).
  services.imperium.blocky = {
    enable = true;
    port = 5335;
  };
}
