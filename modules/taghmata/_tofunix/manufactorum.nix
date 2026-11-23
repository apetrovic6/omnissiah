# Manufactorum: the virtual machines on the Proxmox host at 192.168.1.11
# (the one mars runs on), and the installer they boot.
#
# A VM here is only the hardware. Installing NixOS onto it is still
# `clan machines install <name> --target-host root@<ip>` from the installer
# ISO; after that the machine is managed like any other clan machine.
{config, ...}: {
  manufactorum = {
    # As mars (VM 100): disks on the `storage` thin pool, ISOs on the `iso`
    # NFS share.
    node = "pve2";
    datastore = "storage";
    bridge = "vmbr0";
    installer = "\${proxmox_download_file.nixos_installer.id}";

    vms.ryza = {
      description = "General-purpose clan machine. Managed by tofunix.";
      vmId = 120;
      # Proxmox's OUI, BC:24:11.
      mac = "BC:24:11:5A:6E:01";
      cores = 8;
      memory = 24;
      disk = 200;
    };

    vms.stygies = {
      description = "Dev VM for Hermes and the user. Managed by tofunix.";
      vmId = 121;
      mac = "BC:24:11:5A:6E:02";
      cores = 6;
      memory = 16;
      disk = 150;
    };
  };

  # A pinned release with its checksum, never `latest-…`: the latter changes
  # size on every channel bump, and the provider would download it again.
  resource.proxmox_download_file.nixos_installer = {
    node_name = config.manufactorum.node;
    datastore_id = "iso";
    content_type = "iso";
    url = "https://releases.nixos.org/nixos/26.05/nixos-26.05.14979.94c3211b0ee8/nixos-minimal-26.05.14979.94c3211b0ee8-x86_64-linux.iso";
    checksum = "54034d71971b8937c8e5d85c252053be1a4e010d613d197ba3587dca7548618e";
    checksum_algorithm = "sha256";
    overwrite = false;
  };
}
