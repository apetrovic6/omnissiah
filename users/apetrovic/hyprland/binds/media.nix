
{ config, pkgs, ... }:


{
  home.packages = with pkgs; [
    avizo          # OSD
    pamixer        # used by Avizo's volumectl
    brightnessctl  # used by Avizo's lightctl
    playerctl
  ];

  # Start Avizo as a user service
  systemd.user.services.avizo = {
    Unit = { Description = "Avizo OSD"; };
    Service = {
      ExecStart = "${pkgs.avizo}/bin/avizo-service";
      Restart = "on-failure";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  wayland.windowManager.hyprland.settings = {
    bindeld = [
      # Volume
      ",XF86AudioRaiseVolume,Volume up,exec, ${pkgs.avizo}/bin/volumectl -u up"
      ",XF86AudioLowerVolume,Volume down,exec, ${pkgs.avizo}/bin/volumectl -u down"
      ",XF86AudioMute,Mute,exec, ${pkgs.avizo}/bin/volumectl toggle-mute"
      ",XF86AudioMicMute,Mute mic,exec, ${pkgs.avizo}/bin/volumectl -m toggle-mute"

      # Brightness
      ",XF86MonBrightnessUp,Brightness up,exec, ${pkgs.avizo}/bin/lightctl up"
      ",XF86MonBrightnessDown,Brightness down,exec, ${pkgs.avizo}/bin/lightctl down"

      # Precise 1% (ALT)
      "ALT,XF86AudioRaiseVolume,Volume +1,exec, ${pkgs.avizo}/bin/volumectl -u +1"
      "ALT,XF86AudioLowerVolume,Volume -1,exec, ${pkgs.avizo}/bin/volumectl -u -1"
      "ALT,XF86MonBrightnessUp,Brightness +1,exec, ${pkgs.avizo}/bin/lightctl +1"
      "ALT,XF86MonBrightnessDown,Brightness -1,exec, ${pkgs.avizo}/bin/lightctl -1"

      # Media keys (no OSD, just control)
      ", XF86AudioNext,Next,exec, ${pkgs.playerctl}/bin/playerctl next"
      ", XF86AudioPause,Play/Pause,exec, ${pkgs.playerctl}/bin/playerctl play-pause"
      ", XF86AudioPlay,Play/Pause,exec, ${pkgs.playerctl}/bin/playerctl play-pause"
      ", XF86AudioPrev,Prev,exec, ${pkgs.playerctl}/bin/playerctl previous"

      # Your custom output switch
      "SUPER, XF86AudioMute, Switch output, exec, omarchy-cmd-audio-switch"
    ];
  };
}

