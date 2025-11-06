{config, lib, ...}:
let 
  #inherit (lib) toString;
 opacity = config.stylix.opacity;
in
{
  wayland.windowManager.hyprland.settings = {
    # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more

    windowrulev2 = [
      "suppressevent maximize, class:.*"
      "opacity ${toString opacity.applications} ${toString (opacity.applications - 0.2) }, class:^(?!(ghostty|kitty|alacritty)$).*"

      # Fix some dragging issues with XWayland
      "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
    ];

  };
}
