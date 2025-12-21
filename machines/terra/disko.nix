# ---
# schema = "single-disk"
# [placeholders]
# mainDisk = "/dev/disk/by-id/nvme-CT500P310SSD8_25295198870D"
# ---
# This file was automatically generated!
# CHANGING this configuration requires wiping and reinstalling the machine
{...}: let
  diskId = "/dev/disk/by-id/nvme-CT500P310SSD8_25295198870D";
in {
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = true;
  disko.devices = {
    disk = {
      main = {
        name = "main-4f01a3074d3c4fd99dc55004f7a69ab4";
        device = diskId;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            "boot" = {
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
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
