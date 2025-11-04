
{ lib, config, self, pkgs,... }:

let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.services.magos.stylix;
in
{
  imports = [
    self.inputs.stylix.nixosModules.stylix
  ];

  options.services.magos.stylix = {
    enable = mkEnableOption "Enable Stylix";

    image = mkOption {
      type = types.path;
      default = ./../../wallpapers/lofi/3.jpg;
      description = "Path to the wallpaper image to use.";
    };

    polarity = mkOption {
      type = types.enum [ "light" "dark" ];
      default = "dark";
      description = "Polarity of the theme.";
    };
  };

  # Gate actual config behind the enable flag.
  config = mkIf cfg.enable {
    stylix = {
      enable = true;
      image = cfg.image;
      polarity = cfg.polarity;

      targets.regreet = {
        enable = true;
        useWallpaper = true;
      };

     cursor = {
        package = pkgs.adwaita-icon-theme;
        name = "Adwaita";
        size = 24;
  };
    };
  };
}

