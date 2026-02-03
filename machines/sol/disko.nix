let
  bootDiskId = "/dev/disk/by-id/nvme-KINGSTON_SFYRD2000G_50026B7383CCF4B8";
  storageDiskId = "/dev/disk/by-id/nvme-WD_Red_SN700_2000GB_25421G800787";
in {
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = true;
  disko.devices = {
    disk = {
      main = {
        name = "main-2d04b2e06dd7486b982cad99cadf6a82";
        device = bootDiskId;
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

      storage = {
        type = "disk";
        device = storageDiskId;
        content = {
          type = "gpt";
          partitions = {
            storage = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/storage";
              };
            };
          };
        };
      };
    };
  };
}
