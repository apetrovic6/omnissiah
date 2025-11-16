{
  self,
  lib,
  ...
}: let
  diskId = "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092";
in {
  imports = [
    self.inputs.nix-flatpak.nixosModules.nix-flatpak
    self.inputs.nixos-hardware.nixosModules.asus-zephyrus-gu605my
    self.nixosModules.impermanence
    self.nixosModules.zram
    self.inputs.lanzaboote.nixosModules.lanzaboote
  ];

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  services.imperium.zram.enable = true;

  services.imperium.impermanence = {
    enable = true;
  };
  #boot.initrd.luks.devices."enc".device = diskId;

  users.mutableUsers = false;
  services.dbus.enable = true;
  security.polkit.enable = true;
  # services.logind.enable = true;

  # systemd Stage 1: if enabled, it handles unlocking of LUKS-encrypted volumes during boot.
  boot.initrd.luks.devices = {
    cryptroot = {
      device = "/dev/disk/by-partlabel/luks";
      allowDiscards = true;
    };
  };
  # This complements using zram, putting /tmp on RAM
  boot = {
    tmp = {
      useTmpfs = true;
      tmpfsSize = "50%";
    };
  };

  # Enable autoScrub for btrfs
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = ["/"];
  };

  boot.initrd.systemd = {
    # enable = lib.mkDefault true; # this enabled systemd support in stage1 - required for the below setup
    services.rollback = {
      description = "Rollback BTRFS root subvolume to a pristine state";
      wantedBy = ["initrd.target"];

      # LUKS/TPM process. If you have named your device mapper something other
      # than 'enc', then @enc will have a different name. Adjust accordingly.
      after = ["systemd-cryptsetup@cryptroot.service"];

      # Before mounting the system root (/sysroot) during the early boot process
      before = ["sysroot.mount"];

      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /mnt

        # We first mount the BTRFS root to /mnt
        # so we can manipulate btrfs subvolumes.
        mount -o subvol=/ /dev/mapper/cryptroot /mnt

        # While we're tempted to just delete /root and create
        # a new snapshot from /root-blank, /root is already
        # populated at this point with a number of subvolumes,
        # which makes `btrfs subvolume delete` fail.
        # So, we remove them first.
        #
        # /root contains subvolumes:
        # - /root/var/lib/portables
        # - /root/var/lib/machines

        btrfs subvolume list -o /mnt/root |
          cut -f9 -d' ' |
          while read subvolume; do
            echo "deleting /$subvolume subvolume..."
            btrfs subvolume delete "/mnt/$subvolume"
          done &&
          echo "deleting /root subvolume..." &&
          btrfs subvolume delete /mnt/root
        echo "restoring blank /root subvolume..."
        btrfs subvolume snapshot /mnt/root-blank /mnt/root

        # Once we're done rolling back to a blank snapshot,
        # we can unmount /mnt and continue on the boot process.
        umount /mnt
      '';
    };
  };
  boot.loader = {
    systemd-boot.enable = false;
    efi.canTouchEfiVariables = false;
    grub.devices = [
      "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092"
    ];
  };
}
