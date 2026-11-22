# ryza's disk: btrfs subvolumes for impermanence (configuration.nix). The root
# subvolume is reset to `root-blank` on every boot; only /nix and /persist are
# kept, and configuration.nix lists what is bind-mounted from /persist. No
# LUKS: an unattended VM has no one to type a passphrase at boot.
#
# CHANGING this configuration requires wiping and reinstalling the machine.
{
  boot.loader.grub = {
    efiInstallAsRemovable = true;
    efiSupport = true;
  };

  disko.devices.disk.main = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # for grub MBR
          priority = 1;
        };
        ESP = {
          type = "EF00";
          size = "500M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        root = {
          size = "100%";
          # A fixed name, so the rollback in the initrd can wait for this
          # device (configuration.nix).
          label = "ryza-root";
          content = {
            type = "btrfs";
            extraArgs = ["-f"];
            subvolumes = let
              opts = ["compress=zstd" "noatime"];
            in {
              "/root" = {
                mountpoint = "/";
                mountOptions = opts;
              };
              "/root-blank" = {};
              "/nix" = {
                mountpoint = "/nix";
                mountOptions = opts;
              };
              "/persist" = {
                mountpoint = "/persist";
                mountOptions = opts;
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
}
