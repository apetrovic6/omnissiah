{self, pkgs, ... }:
{
  imports = [
    ./binds
  ];

 wayland.windowManager.hyprland = {
            enable = true;
            # set the flake package
            package = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
            portalPackage = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };
}
