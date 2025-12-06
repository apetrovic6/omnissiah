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

  # magos.hyprland.monitor = ",3840x2160@120,1";

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

  services.imperium.lanzaboote.enable = false;
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
      diskId
    ];
  };
}
