{self, ...}:
{

      imports = [
        self.inputs.nix-flatpak.nixosModules.nix-flatpak
    #        self.inputs.nixos-hardware.nixosModules.asus-zephyrus-gu605my

        ../../modules/cosmic.nix
      ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = false;
    grub.devices = [
      "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092"
    ];
  };
  
}
