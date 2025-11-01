{...}:
{
  services.hypridle = {
    enable = true;
    systemdTarget = "hyprland-session.target";

    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";       # avoid starting multiple hyprlock instances.
        before_sleep_cmd = "loginctl lock-session";    # lock before suspend.
        after_sleep_cmd = "hyprctl dispatch dpms on";  # to avoid having to press a key twice to turn on the display.
      };

    
      listener = [
        {
        timeout = 150;                                # 2.5min.
        on-timeout = "brightnessctl -s set 10";         # set monitor backlight to minimum, avoid 0 on OLED monitor.
        on-resume = "brightnessctl -r";                 # monitor backlight restore.
      }

      # turn off keyboard backlight, comment out this section if you dont have a keyboard backlight.
       { 
        timeout = 150;                                         # 2.5min.
        on-timeout = "brightnessctl -sd rgb:kbd_backlight set 0"; # turn off keyboard backlight.
        on-resume = "brightnessctl -rd rgb:kbd_backlight";        # turn on keyboard backlight.
      }

        {
          timeout = 300; # 5min. 
          on-timeout = "loginctl lock-session"; # Lock screen after timeout has passed
        }

        {
          timeout = 1800; #3 0min
          on-timeout = "systemctl suspend"; # suspend pc
        }
    ];
    };
  };
}
