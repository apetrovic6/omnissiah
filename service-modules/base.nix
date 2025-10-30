{
  _class = "clan.service";
  manifest.name = "base";

  roles.default.perInstance.nixosModule = { lib, pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      btop
      pciutils
      nvim
      vim
      wget
      git
      fastfetch
      yazi
      killall
      lm-sensors
    ];
  };

  nix.gc.automatic = true;
  nix.settings.auto-optimise-store = true;

  services.xserver = {
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  services.tailscale = {
    enable = true;
  };
}
