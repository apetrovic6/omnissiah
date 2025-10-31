{self, pkgs, lib, config, ...}:
let 
  inherit (lib) mkIf mkOption types;
  cfg = config.services.imperium.hyprland;
in
{
    
options.services.imperium.hyprland = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Hyprland setup on the Imperial machines";
    };
  };


  config = mkIf cfg.enable {
  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };

  environment.variables = {
    GDK_BACKEND = "wayland,x11,*"
  };

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;

    # package = self.inputs.hyprland.packages.x86_64-linux.hyprland;
   
    # set the flake package
    package = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # make sure to also set the portal package, so that they are in sync
    portalPackage = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  environment.systemPackages = with pkgs; [
    # hyprpaper
    # hyprpicker
    # waybar-hyprland
    wlogout
    # mako
    # grimblast
    # swaybg
    wl-clipboard
    # wf-recorder
    # xdg-desktop-portal-hyprland
    qt5.qtwayland
    qt6.qtwayland
  ];
  };

}
