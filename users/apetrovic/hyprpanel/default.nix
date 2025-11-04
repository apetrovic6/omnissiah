{config, lib, ...}:
{
 # programs.hyprpanel.settings.theme.bar.buttons.hover = lib.mkForce {
 #    # Keep the color if you still want a hover color:
 #    # color = "#1b7679";
 #
 #    background = {
 #      opacity = 70;
 #    };
 #  };

  programs.hyprpanel = {
    enable = true;
    systemd.enable = true;
    # Configure and theme almost all options from the GUI.
    # See 'https://hyprpanel.com/configuration/settings.html'.
    settings = {

      # Configure bar layouts for monitors.
      # See 'https://hyprpanel.com/configuration/panel.html'.
      # Default: null
      bar.layouts = {
        "*" = {
          left = [ "dashboard" "workspaces" "media" "cava"];
          middle = [ "clock"];
          right = [  "volume" "network" "bluetooth"  "battery" "notifications" "kbinput" "systray"];
        };
      };

     scalingPriority = "hyprland";
      bar.launcher.autoDetectIcon = true;
      bar.workspaces = {
        monitorSpecific = false;
        show_icons = true;
      };


      bar.bluetooth.label = true;

      menus.clock = {
        time = {
          military = true;
          hideSeconds = true;
        };
        weather.unit = "metric";
      };

      menus.dashboard.directories.enabled = false;
      menus.dashboard.stats.enable_gpu = false;

      theme = {
        bar = {
          transparent = true;
          buttons =  {
            enableBorders = true;
            hover = lib.mkForce {
              background.opacity = 50;
            };
          };
        };

      osd = {
        orientation = "horizontal";

        location = "bottom";
        margins = "7px 7px 70px 7px";
        enableShadow = true;
        muteVolumeAsZero = true;
      };

        volume.allowRaisingVolumeAbove100 = false;


      font = {
         name = config.stylix.fonts.monospace.name;
         size = "${toString config.stylix.fonts.sizes.desktop}px";
        };
      };
    };
  };
}
