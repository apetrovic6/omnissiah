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

  # A strict ephemeral root (disko.nix): only /nix and /persist survive a
  # reboot, and from /persist only what is listed here (plus the shared
  # module's few defaults, such as /var/lib/nixos and /root). Not even /etc:
  # it is rebuilt from the configuration on every boot. A service that keeps
  # state somewhere unlisted loses it on reboot, so a new service on ryza
  # adds its state directory here.
  services.imperium.impermanence = {
    enable = true;
    keepEtc = false;
    # Plain btrfs, no LUKS: wait for the partition, not for an unlock.
    rollback = {
      device = "/dev/disk/by-partlabel/ryza-root";
      after = ["dev-disk-by\\x2dpartlabel-ryza\\x2droot.device"];
    };
    directories = [
      "/var/log"
      # Persistent timers, the random seed, linger.
      "/var/lib/systemd"
      {
        directory = "/var/lib/hermes";
        user = "hermes";
        group = "hermes";
        mode = "0700";
      }
      # The CI microVM's disk images (100 GiB store overlay, 40 GiB /var).
      {
        directory = "/var/lib/microvms";
        user = "microvm";
        group = "kvm";
        mode = "0775";
      }
      # DynamicUser state: Blocky's list cache, the runner's cargo cache.
      {
        directory = "/var/lib/private";
        mode = "0700";
      }
      "/var/lib/blocky-nrd"
      # Guard state. The onion key itself comes from clan vars.
      {
        directory = "/var/lib/tor";
        user = "tor";
        group = "tor";
        mode = "0700";
      }
    ];
  };

  # /etc/machine-id from a clan var, as /etc is not kept.
  clan.core.settings.machine-id.enable = true;

  # The sops age key is read before the bind mounts exist, so it lives on the
  # persistent subvolume itself; `clan machines install` uploads it there.
  clan.core.vars.sops.secretUploadDirectory = "/persist/var/lib/sops-nix";

  # Copy-on-write fragments VM images badly on btrfs, so files created in the
  # microVM directory get NOCOW. It only applies to files created after the
  # flag, which on a fresh install is all of them. Set on /persist, the real
  # directory, rather than on the bind mount.
  systemd.tmpfiles.rules = ["h /persist/var/lib/microvms - - - - +C"];

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
