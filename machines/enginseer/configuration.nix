{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  diskId = "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092";
in {
  imports = [
    self.inputs.nix-flatpak.nixosModules.nix-flatpak
    self.inputs.nixos-hardware.nixosModules.asus-zephyrus-gu605my
    self.nixosModules.impermanence
    self.nixosModules.zram
    self.nixosModules.lanzaboote
    self.nixosModules.vars
    self.nixosModules.smb
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
  #

  magos.core.hyprland.monitor = ",2560x1600@240,auto,1.33";
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
      "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092"
    ];
  };
}
