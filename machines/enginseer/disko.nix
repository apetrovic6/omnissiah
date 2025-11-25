# ---
# schema = "single-disk"
# [placeholders]
# mainDisk = "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092"
# ---
# This file was automatically generated!
# CHANGING this configuration requires wiping and reinstalling the machine
{lib, ...}: let
  diskId = "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092";
in {
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = false;

  swapDevices = [
    {
      device = "/persist/swap/swapfile";
      size = 18 * 1024; # Size in MB (18GB)
      # or
      # size = 16384; # Size in MB (16G);
    }
  ];

  disko.devices = {
    disk = {
      nvme0n1 = {
        type = "disk";
        # Make sure this is correct with `lsblk`
        device = diskId;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              label = "boot";
              name = "ESP";
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                ];
              };
            };
            luks = {
              size = "100%";
              label = "luks";
              content = {
                type = "luks";
                name = "cryptroot";
                content = {
                  type = "btrfs";
                  extraArgs = ["-L" "nixos" "-f"];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = ["subvol=root" "compress=zstd" "noatime"];
                    };
                    "/root-blank" = {
                      mountOptions = ["subvol=root-blank" "nodatacow" "noatime"];
                    };
                    # "/home" = {
                    #   mountpoint = "/home";
                    #   mountOptions = ["subvol=home" "compress=zstd" "noatime"];
                    # };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["subvol=nix" "compress=zstd" "noatime"];
                    };
                    "/persist" = {
                      mountpoint = "/persist";
                      mountOptions = ["subvol=persist" "compress=zstd" "noatime"];
                    };
                    "/log" = {
                      mountpoint = "/var/log";
                      mountOptions = ["subvol=log" "compress=zstd" "noatime"];
                    };
                    "/lib" = {
                      mountpoint = "/var/lib";
                      mountOptions = ["subvol=lib" "compress=zstd" "noatime"];
                    };
                    "/persist/swap" = {
                      mountpoint = "/persist/swap";
                      mountOptions = ["subvol=swap" "noatime" "nodatacow" "compress=no"];
                      swap.swapfile.size = "64G";
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
  fileSystems."/var/lib".neededForBoot = true; # };
}
