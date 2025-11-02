{self, pkgs, ... }:
{
  imports = [
    ./binds
    ./hypridle
    ./hyprlock
    ./exec.nix
    ./config
  ];

 wayland.windowManager.hyprland = {
            enable = true;
            systemd.enable = true;
            # set the flake package
            package = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
            portalPackage = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;

    settings = {
      decoration = {
        rounding = 10;


      blur = {
        enabled = true;
        size =  10;
        passes = 2;
        contrast = 1.5;
        ignore_opacity = true;
        new_optimizations = true;
        popups = true;
       };
      };
    };
  };
}
