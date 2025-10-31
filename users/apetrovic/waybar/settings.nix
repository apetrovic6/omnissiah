{config, lib, ...}:
let
  betterTransition = "all 0.3s cubic-bezier(.55,-0.68,.48,1.682)";
in
with lib; 
{
  programs.waybar.settings = [
 {
        layer = "top";
        position = "top";
        modules-center = [ "clock"  ];
        modules-left = [
          "custom/startmenu"
          "hyprland/workspaces"
        ];
        modules-right = [
          "group/tray-expander"
          "memory"
          "bluetooth"
          "pulseaudio"
          "cpu"
          "battery"
        ];

      "group/tray-expander" = {
        orientation = "inherit";
        drawer = {
          transition-duration =  600;
          children-class  = "tray-group-item";
         };
        modules = [
          "custom/expand-icon" 
          "tray"
          "idle_inhibitor"
          "cpu"
        ];
       };

      "custom/expand-icon" = {
        format =  "";
        tooltip = false;
      };

  "hyprland/workspaces" = {
      #            format = "{icon} {windows}";
        #
  on-scroll-up = "hyprctl dispatch workspace e+1";
          on-scroll-down = "hyprctl dispatch workspace e-1";
      format = "{icon}";
      all-outputs = true;
      on-click = "activate";
      format-icons = {
        active = "󰮯";
        default = "󰊠";
        persistent = "󰊠";
      };
      persistent-workspaces = {
        "1" = [ ];
        "2" = [ ];
        "3" = [ ];
        "4" = [ ];
        "5" = [ ];
        # "6" = [];
        # "7" = [];
        # "8" = [];
        # "9" = [];
        # "10" = [];
      };

      "window-rewrite-default" = " ";
      "window-rewrite" = {
        "title<.*youtube.*>" = " ";
        "title<.*Picture in Picture.*>" = " ";
        "class<thunar>" = " 󰝰";
        "class<firefox|brave>" = " ";
        "class<alacritty|wezterm|kitty>" = " ";
        "title<nvim>" = " ";
        "title<.*reddit.*>" = " ";
        "title<.*Microsoft Teams.*>" = " 󰊻";
        "title<.*Mail.*>" = " ";
        "title<.*Discord.*" = " ";
      };
    };

  "bluetooth" = {
    "format"=  "";
    "format-disabled" = "󰂲";
    "format-connected" =  "";
    "tooltip-format" = "Devices connected: {num_connections}";
    "on-click" = "bluetui";
  };

        "clock" = {
        format = "{:L%A %H:%M}";
          "format-alt" = "{:L%d %B W%V %Y}";
          tooltip = false;
          tooltip-format = "<big>{:%A, %d.%B %Y }</big>\n<tt><small>{calendar}</small></tt>";
        };
        "hyprland/window" = {
          max-length = 22;
          separate-outputs = false;
          rewrite = {
            "" = " 🙈 No Windows? ";
          };
        };

        "memory" = {
          interval = 5;
          format = " {}%";
          tooltip = true;
        };

        "cpu" = {
          interval = 5;
          format = " {usage:2}%";
          tooltip = true;
        };
        "disk" = {
          format = " {free}";
          tooltip = true;
        };
        "network" = {
          format-icons = [
            "󰤯"
            "󰤟"
            "󰤢"
            "󰤥"
            "󰤨"
          ];
          format-ethernet = " {bandwidthDownOctets}";
          format-wifi = "{icon} {signalStrength}%";
          format-disconnected = "󰤮";
          tooltip = false;
        };
        "tray" = {
          spacing = 12;
        };
        "pulseaudio" = {
          format = "{icon} {volume}% {format_source}";
          format-bluetooth = "{volume}% {icon} {format_source}";
          format-bluetooth-muted = " {icon} {format_source}";
          format-muted = " {format_source}";
          format-source = " {volume}%";
          format-source-muted = "";
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [
              ""
              ""
              ""
            ];
          };
          on-click = "sleep 0.1 && pavucontrol";
        };
        "custom/exit" = {
          tooltip = false;
          format = "";
          on-click = "sleep 0.1 && wlogout";
        };
        "custom/startmenu" = {
          tooltip = false;
          format = "";
          # exec = "rofi -show drun";
          #on-click = "sleep 0.1 && rofi-launcher";
          on-click = "sleep 0.1 && nwg-drawer -mb 200 -mt 200 -mr 200 -ml 200";
        };
        "custom/hyprbindings" = {
          tooltip = false;
          format = "󱕴";
          on-click = "sleep 0.1 && list-keybinds";
        };
        "idle_inhibitor" = {
          format = "{icon}";
          format-icons = {
            activated = "";
            deactivated = "";
          };
          tooltip = "true";
        };
        "custom/notification" = {
          tooltip = false;
          format = "{icon} {}";
          format-icons = {
            notification = "<span foreground='red'><sup></sup></span>";
            none = "";
            dnd-notification = "<span foreground='red'><sup></sup></span>";
            dnd-none = "";
            inhibited-notification = "<span foreground='red'><sup></sup></span>";
            inhibited-none = "";
            dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
            dnd-inhibited-none = "";
          };
          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "sleep 0.1 && task-waybar";
          escape = true;
        };
        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󱘖 {capacity}%";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          on-click = "";
          tooltip = false;
        };
      }
    ];

    programs.waybar.style = concatStrings [
      ''
  * {
          font-size: 15px;
          border-radius: 0px;
          border: none;
          min-height: 0px;
          margin: 0 5px;
        }

        window#waybar {
          background: rgba(0,0,0,0);
        }

        #window, #pulseaudio, #cpu, #memory, #idle_inhibitor, #workspaces, #clock, #custom-startmenu {
          font-weight: bold;
          margin: 4px 4px;
          padding: 0px 18px;
          background: #${config.lib.stylix.colors.base00};
          color: #${config.lib.stylix.colors.base08};
          border-radius: 8px 8px 8px 8px;
        }

        #workspaces button {
          opacity: 1;
          border-radius: 20px;
          padding: 0 5px;
          margin: 5px  2px;
          transition: ${betterTransition};
        }

        #workspaces button.active {
          color: #${config.lib.stylix.colors.base00};
          background:  #${config.lib.stylix.colors.base08};
          transition: ${betterTransition};
          opacity: 1.0;
        }

        #workspaces button:hover {
          font-weight: bold;
          border-radius: 16px;
          color: #${config.lib.stylix.colors.base00};
          background:  #${config.lib.stylix.colors.base08};
          opacity: 0.8;
          transition: ${betterTransition};
        }

        tooltip {
          background: #${config.lib.stylix.colors.base00};
          border: 1px solid #${config.lib.stylix.colors.base08};
          border-radius: 12px;
        }

        tooltip label {
          color: #${config.lib.stylix.colors.base08};
        }

        #idle_inhibitor {
        }

        #custom-startmenu {
        }

        #custom-hyprbindings, #network, #battery,
        #custom-notification, #tray, #custom-exit {
          font-size: 20px;
          background: #${config.lib.stylix.colors.base00};
          color: #${config.lib.stylix.colors.base08};
          margin: 4px 0px;
          margin-right: 7px;
          border-radius: 8px 8px 8px 8px;
          padding: 0px 18px;
        }

        #clock {
        }
      ''
    ];
}

