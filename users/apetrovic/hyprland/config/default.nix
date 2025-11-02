{...}:
{
  imports = [
    ./windows.nix
    ./input.nix
    ./monitors.nix
    ./animations.nix
  ];


 wayland.windowManager.hyprland.settings = {
    general = {
      gaps_in = 5;
      gaps_out = 10;

      resize_on_border = false;
      allow_tearing = false;

      layout = "dwindle";
    };

    master = {
      new_status = "master";
    };
    #
    # https://wiki.hyprland.org/Configuring/Variables/#misc
    misc = {
      disable_hyprland_logo = true;
      disable_splash_rendering  = true;
      focus_on_activate = true;
      anr_missed_pings = 3;
      new_window_takes_over_fullscreen = 1;
    };

    cursor = {
      hide_on_key_press = true;
    };

    dwindle =  {
      pseudotile = true; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
      preserve_split = true; # You probably want this
      force_split = 2; # Always split on the right
    };

    xwayland =  {
      force_zero_scaling = true;
    };
  };

}
