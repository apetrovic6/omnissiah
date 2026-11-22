# ryza: the general-purpose VM on the Proxmox host at 192.168.1.11, next to
# mars. The VM itself is declared in tofunix
# (modules/taghmata/_tofunix/manufactorum.nix); this is what runs inside it.
# Meant for CI runners for both forges and for the always-on agent.
{self, ...}: {
  imports = [
    self.nixosModules.blocky
    self.nixosModules.impermanence
    ./network.nix
    ./forgejo-runner.nix
    ./hermes.nix
  ];

  # An ephemeral root (disko.nix). The shared module keeps /etc and a few
  # paths; /var/lib and /var/log are their own subvolumes, so all service
  # state survives (Hermes, the CI microVM, Blocky, the sops key). /home, /tmp,
  # /var/cache and anything else written by hand go away on reboot.
  services.imperium.impermanence = {
    enable = true;
    # Plain btrfs, no LUKS: wait for the partition, not for an unlock.
    rollback = {
      device = "/dev/disk/by-partlabel/ryza-root";
      after = ["dev-disk-by\\x2dpartlabel-ryza\\x2droot.device"];
    };
  };

  # The CI VM's disk images live here (100 GiB store overlay, 40 GiB /var).
  # Copy-on-write fragments VM images badly on btrfs, so files created in
  # this directory get NOCOW. It only applies to files created after the
  # flag, which on a fresh install is all of them.
  systemd.tmpfiles.rules = [
    "d /var/lib/microvms 0775 microvm kvm -"
    "h /var/lib/microvms - - - - +C"
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
