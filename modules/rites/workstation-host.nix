# What the workstations (phalanx, enginseer) share as hosts, as opposed to the
# desktop and tooling the `workstation` role (stc/workstation.nix) puts on
# them: the encrypted btrfs root with secure boot and impermanence, the NVIDIA
# driver settings, and the NAS shares.
#
# Each machine imports this and sets what is its own: the
# boot disk, the rest of its hardware, and anything only it runs.
{self, ...}: {
  flake.nixosModules.workstation-host = {...}: {
    imports = [
      self.inputs.nix-flatpak.nixosModules.nix-flatpak
      self.nixosModules.impermanence
      self.nixosModules.zram
      self.nixosModules.lanzaboote
      self.nixosModules.vars
      self.nixosModules.smb
    ];

    nixpkgs.config = {
      allowUnfree = true;
      microsoftVisualStudioLicenseAccepted = true; # PipeASIO (Rocksmith)
    };

    hardware.nvidia.open = true;
    hardware.nvidia.powerManagement.enable = true;

    services.imperium.lanzaboote.enable = true;
    services.imperium.zram.enable = true;
    services.imperium.impermanence.enable = true;

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
    boot.tmp = {
      useTmpfs = true;
      tmpfsSize = "50%";
    };

    boot.loader.efi.canTouchEfiVariables = false;

    # Enable autoScrub for btrfs
    services.btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = ["/"];
    };

    services.imperium.smb.enable = true;

    services.imperium.smb.hosts.manjaca = {
      host = self.lib.hosts.manjaca;
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
    };
  };
}
