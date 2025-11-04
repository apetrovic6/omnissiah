{...}:
{
  # https://wiki.hyprland.org/Configuring/Variables/#input
 wayland.windowManager.hyprland.settings.input =  {
    kb_layout = "us,hr";
    kb_variant = "";
    kb_model = "";
    kb_options = "grp:alt_shift_toggle";  # Alt+Shift cycles layouts
    kb_rules = "";

    follow_mouse = 1;

    sensitivity = 0; # -1.0 - 1.0, 0 means no modification.

    touchpad = {   natural_scroll = false;};
  };
}
