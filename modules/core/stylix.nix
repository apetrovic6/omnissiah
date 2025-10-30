{ pkgs, ...}:
{
  stylix = {
    enable = true;
    image = ../../wallpapers/everforest/1.png;
    polarity = "dark";
    opacity.terminal = 0.7;

 fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-mono;
        name = "Fira Mono";
      };

      sizes = {
        applications = 12;
        terminal = 15;
        desktop = 11;
        popups = 12;
      };
  };
  };
}
