
{ pkgs, lib, ... }:
let 
  inherit (lib) getExe;
in
{
  home.packages = with pkgs; [
    playerctl
  ];

  # Hyprland binds that *trigger* Hyprpanel's OSD by changing system state.
  wayland.windowManager.hyprland.settings = with pkgs; {
    # Volume
    bindeld = [
      # Volume
      ",XF86AudioRaiseVolume,Vol up,exec, ${wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
      ",XF86AudioLowerVolume,Vol down,exec, ${wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
      ",XF86AudioMute,Mute,exec, ${wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      ",XF86AudioMicMute,Mute mic,exec, ${wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"

      # Precise 1%
      "ALT,XF86AudioRaiseVolume,Vol +1,exec, ${wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+"
      "ALT,XF86AudioLowerVolume,Vol -1,exec, ${wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"
      "ALT,XF86MonBrightnessUp,Brightness +1,exec, ${brightnessctl}/bin/brightnessctl set +1%"
      "ALT,XF86MonBrightnessDown,Brightness -1,exec, ${brightnessctl}/bin/brightnessctl set 1%-"

      # Media keys (no OSD needed)
      ",XF86AudioNext,Next,exec, ${playerctl}/bin/playerctl next"
      ",XF86AudioPause,Play/Pause,exec, ${getExe playerctl} play-pause"
      ",XF86AudioPlay,Play/Pause,exec, ${getExe playerctl} play-pause"
      ",XF86AudioPrev,Prev,exec, ${getExe playerctl} previous"

      # Your custom output switch
      "SUPER,XF86AudioMute,Switch output,exec, omarchy-cmd-audio-switch"


      # Brightness
      ",XF86MonBrightnessUp,Brightness up,exec, ${getExe brightnessctl} -d intel_backlight set 5%+"
      ",XF86MonBrightnessDown,Brightness down,exec, ${getExe brightnessctl} -d intel_backlight set 5%-"
    ];
  };
}

