{self, pgks,...}:
{

      imports = [
        self.inputs.nixos-hardware.nixosModules.asus-zephyrus-gu605my
      ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = false;
    grub.devices = [
      "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092"
    ];
  };
  

  services.displayManager.cosmic-greeter.enable = true;
  services.desktopManager.cosmic = {
    enable = true;
    xwayland.enable = true;
  };

  nixpkgs.config.allowUnfree = true;
}
