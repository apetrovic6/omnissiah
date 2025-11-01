{ pkgs, ...}:
{
  stylix = {
    enable = true;
    autoEnable = true;
    image = ../../wallpapers/lofi/3.jpg;
    polarity = "dark";

    opacity = {
      terminal = 0.8;
      desktop = 0.5;
      popups = 0.5;
      applications = 0.5;
    };

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-mono;
        name = "fira-mono";
      };

      sizes = {
        applications = 10;
        terminal = 10;
        desktop = 10;
        popups = 10;
      };
  };

    targets = {
      alacritty = {
        enable = true;
      };

    ghostty = {
      enable = true;
    };

    yazi.enable = true;
    bat.enable = true;
    cava.enable = true;
    btop.enable = true;
    vesktop.enable = true;  
    lazygit.enable = true;
    vim.enable = true;
    qt.enable = true;
    qutebrowser.enable = true;
    starship.enable = true;
    swaync.enable = true;
    zathura.enable = true;
    obsidian.enable = true;
    fzf.enable = true;


    nvf = {
        enable = true;
      };

    hyprland = {
      enable = true;
    };

    hyprlock = {
      enable = true;
      useWallpaper = true;
    };

      librewolf = {
        enable = true;
        colorTheme.enable = true;
        profileNames = [ "apetrovic" ];
      };


    waybar = {
      enable = true;
      font = "monospace";
      addCss = false;
    };
    };
  };
}
