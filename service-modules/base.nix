{
  _class = "clan.service";
  manifest.name = "base";

  roles.default.description = "Some basic tools and settings that are needed everywhere";

  roles.default.perInstance.nixosModule = { lib, pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      btop
      pciutils
      neovim
      vim
      wget
      git
      fastfetch
      yazi
      killall
    ];

    fonts = {
      packages = with pkgs; [
        fira-code
        fira-code-symbols
        fira-mono
      ];
    };

  nix.gc.automatic = true;
  nix.settings.auto-optimise-store = true;

    programs.dconf = {
      enable = true;
    };

  services.xserver = {
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  services.tailscale = {
    enable = true;
  };

  nixpkgs.config.allowUnfree = true;
};
}
