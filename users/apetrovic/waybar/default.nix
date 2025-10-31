{...}:
{
  imports = [
    ./settings.nix
    ./style.nix
  ];

  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      target = "hyprland-session.target";
    };
  };
}
