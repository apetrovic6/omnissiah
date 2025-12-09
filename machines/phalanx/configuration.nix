{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  diskId = "/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_23462Z801872";
in {
  imports = [
    self.inputs.nix-flatpak.nixosModules.nix-flatpak
    # self.inputs.magos.nixosModules
    self.inputs.nixos-hardware.nixosModules.common-cpu-amd
    self.inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    self.nixosModules.impermanence
    self.nixosModules.zram
    self.nixosModules.lanzaboote
    self.nixosModules.vars
    self.nixosModules.smb
    self.inputs.nixvirt.nixosModules.default
  ];

  # nix = {
  #   extraOptions = ''
  #     !include ${config.clan.core.vars.generators.attic-pull-token.files.token.path}
  #     netrc-file = /home/apetrovic/.config/nix/netrc
  #   '';

  #   settings = {
  #     trusted-public-keys = [
  #       "manjo:NYye+6m7jUVm3d9GUoIjXeX55/sz9xnRP/gl8THza6k="
  #     ];
  #   };
  # };

  boot = {
    kernelParams = ["amd_iommu=on"];
    kernelModules = ["kvm-amd" "vfio-pci"];
  };

  virtualisation.libvirt = let
    nixvirt = self.inputs.nixvirt;
  in {
    enable = true;
    connections."qemu:///system" = {
      networks = [
        {
          definition =
            nixvirt.lib.network.writeXML
            (nixvirt.lib.network.templates.bridge {
              # pick your own UUID (uuidgen)
              uuid = "b334bce1-4364-4fa8-b26f-d74d3666aab8";
              # this gives you 192.168.71.0/24 with DHCP
              subnet_byte = 71;
              # name and bridge_name default to "default" + "virbr0"
            });
          active = true;
        }
      ];

      pools = [
        {
          # A simple directory-backed pool at /var/lib/libvirt/images/data-vault
          definition = nixvirt.lib.pool.writeXML {
            name = "data-vault"; # libvirt pool name
            uuid = "1d50764c-2d7d-40cf-a1f3-a1cd2c1a8b9d"; # run `uuidgen` and replace
            type = "dir";
            target = {path = "/var/lib/libvirt/images/data-vault";};
          };

          active = true;

          # Create a single disk volume for the VM
          volumes = [
            {
              definition = nixvirt.lib.volume.writeXML {
                # volume name inside the pool
                name = "servitor-nixos-01";
                target = {
                  format = {type = "qcow2";};
                };
                # raw 40 GiB disk (good enough to start; tweak as you like)
                capacity = {
                  count = 65;
                  unit = "GiB";
                };
              };
            }

            {
              definition = nixvirt.lib.volume.writeXML {
                # volume name inside the pool
                name = "terra";
                target = {
                  format = {type = "qcow2";};
                };
                # raw 40 GiB disk (good enough to start; tweak as you like)
                capacity = {
                  count = 65;
                  unit = "GiB";
                };
              };
            }

            {
              definition = nixvirt.lib.volume.writeXML {
                # volume name inside the pool
                name = "luna";
                target = {
                  format = {type = "qcow2";};
                };
                # raw 40 GiB disk (good enough to start; tweak as you like)
                capacity = {
                  count = 65;
                  unit = "GiB";
                };
              };
            }
          ];
        }
      ];

      domains = [
        {
          definition =
            nixvirt.lib.domain.writeXML
            (nixvirt.lib.domain.templates.linux {
              # Libvirt domain name
              name = "servitor-nixos-01";

              # Pick your own UUID: `uuidgen`
              uuid = "cc7439ed-36af-4696-a6f2-1f0c4474d87e";

              # VM RAM
              memory = {
                count = 16;
                unit = "GiB";
              };

              # Attach the disk volume we just defined
              storage_vol = {
                pool = "data-vault";
                volume = "servitor-nixos-01";
              };

              # Boot from a NixOS ISO to install:
              # Put the ISO here (or adjust the path)
              # install_vol =
              #   /var/lib/libvirt/iso/nixos-minimal-25.11.iso;

              virtio_video = false;
              # Attach to the default libvirt bridge
              bridge_name = "virbr0";
            });

          # Have NixVirt ensure the domain is running
          # (set to false if you don't want it autostarting)
          active = true;
        }

        {
          definition =
            nixvirt.lib.domain.writeXML
            (nixvirt.lib.domain.templates.linux {
              # Libvirt domain name
              name = "terra";

              # Pick your own UUID: `uuidgen`
              uuid = "558d01d6-9656-4930-aba3-ea05f0d98e70";

              # VM RAM
              memory = {
                count = 16;
                unit = "GiB";
              };

              # Attach the disk volume we just defined
              storage_vol = {
                pool = "data-vault";
                volume = "terra";
              };

              # Boot from a NixOS ISO to install:
              # Put the ISO here (or adjust the path)
              # install_vol =
              #   /var/lib/libvirt/iso/nixos-minimal-25.11.iso;

              virtio_video = false;
              # Attach to the default libvirt bridge
              bridge_name = "virbr0";
            });

          # Have NixVirt ensure the domain is running
          # (set to false if you don't want it autostarting)
          active = true;
        }

        {
          definition =
            nixvirt.lib.domain.writeXML
            (nixvirt.lib.domain.templates.linux {
              # Libvirt domain name
              name = "luna";

              # Pick your own UUID: `uuidgen`
              uuid = "1ea32446-1f3b-4bdb-b254-256582da5511";

              # VM RAM
              memory = {
                count = 16;
                unit = "GiB";
              };

              # Attach the disk volume we just defined
              storage_vol = {
                pool = "data-vault";
                volume = "luna";
              };

              # Boot from a NixOS ISO to install:
              # Put the ISO here (or adjust the path)
              # install_vol =
              #   /var/lib/libvirt/iso/nixos-minimal-25.11.iso;

              virtio_video = false;
              # Attach to the default libvirt bridge
              bridge_name = "virbr0";
            });

          # Have NixVirt ensure the domain is running
          # (set to false if you don't want it autostarting)
          active = true;
        }
      ];
    };
  };

  # Let libvirt’s qemu use the bridge
  virtualisation.libvirtd = {
    allowedBridges = ["virbr0"];
  };

  magos.core.hyprland.monitor = ",3840x2160@120, auto, 1";

  hardware.nvidia.open = true;
  hardware.nvidia.prime.sync.enable = lib.mkForce false;
  hardware.nvidia.prime.offload.enable = lib.mkForce false;

  services.imperium.smb.enable = true;

  services.imperium.smb.hosts.manjaca = {
    host = "192.168.1.61";
    credentialsVarName = "manjaca-nas-credentials";

    shares.games = {
      shareName = "games";
      mountPoint = "/mnt/nas/games";
    };

    shares."3DPrinting" = {
      shareName = "3DPrinting";
      mountPoint = "/mnt/nas/3dprinting";
    };

    shares.home = {
      shareName = "home";
      mountPoint = "/mnt/nas/home";
    };

    shares.data = {
      mountPoint = "/mnt/nas/data";
    };

    shares.uevault = {
      shareName = "UE_VAULT";
      mountPoint = "/mnt/nas/ue_vault";
    };

    shares.docker = {
      mountPoint = "/mnt/nas/ue_vault";
    };
  };

  # boot.loader.systemd-boot.enable = lib.mkForce true;

  services.imperium.lanzaboote.enable = true;
  services.imperium.zram.enable = true;

  hardware.nvidia.powerManagement.enable = true;

  services.imperium.impermanence = {
    enable = true;
  };

  users.mutableUsers = false;
  services.dbus.enable = true;
  security.polkit.enable = true;

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

  boot.loader = {
    efi.canTouchEfiVariables = false;
    grub.devices = [
      "/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_23462Z801872"
    ];
  };
}
