{...}:
{
  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "systemctl --user start hyprpolkitagent"
      "killall -q waybar;sleep .5 && waybar"
      "killall -q swaync;sleep .5 && swaync"
    ];
  };
}
