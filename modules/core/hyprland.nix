{self, pkgs, lib, config, ...}:
let 
  inherit (lib) mkIf mkEnableOption mkOption types optionalAttrs mkMerge optionals;
  cfg = config.services.magos.hyprland;
in
{
    
options.services.magos.hyprland = {

    enable = mkEnableOption "Enable Hyprland";
    xwayland = mkOption {
        type = types.bool;
        default = true;
        description = "Enable xwayland";
      };

    nvidia = {
      enable = mkEnableOption "Enable NVIDIA support";
      modesetting = mkOption {
        type = types.bool;
        default = false;
        description = "Enable kernel modesetting for NVIDIA.";
      };


      powerManagement = mkOption {
        type = types.bool;
        default = false;
        description = "Enable NVIDIA power management";
      };
    };
  };


  config = mkIf cfg.enable {

  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };


  environment.variables = mkMerge [
      {
    GDK_BACKEND = "wayland,x11,*";
    QT_QPA_PLATFORM = "wayland;xcb";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";

    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "Hyprland";

    QT_STYLE_OVERRIDE = "kvantum";
    QT_AUTO_SCREEN_SCALE_FACTOR = 1;
    QT_WAYLAND_DISABLE_WINDOWDECORATION = 1;
    QT_QPA_PLATFORMTHEME = "qt5ct";
    
    MOZ_ENABLE_WAYLAND = 1;

    NIXOS_OZONE_WL = 1;
    }

      (optionalAttrs cfg.nvidia.enable {
        LIBVA_DRIVER_NAME = "nvidia";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      })
    ];


    hardware.nvidia = {
      powerManagement.enable = cfg.nvidia.enable && cfg.nvidia.modesetting;
      modesetting.enable = cfg.nvidia.enable && cfg.nvidia.modesetting;
      };



  programs.hyprland = {
    enable = cfg.enable;
    xwayland.enable = cfg.xwayland;

    # set the flake package
    package = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # make sure to also set the portal package, so that they are in sync
    portalPackage = self.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  environment.systemPackages = with pkgs; [
    # hyprpaper
    # hyprpicker
    wlogout
      adwaita-fonts
    # mako
    # grimblast
    # swaybg
    hyprcursor
    hyprpanel 
    wl-clipboard
    # wf-recorder
    xdg-desktop-portal-hyprland
    qt5.qtwayland
    qt6.qtwayland
  ];


  };

}
