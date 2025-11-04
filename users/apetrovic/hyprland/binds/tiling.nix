{ ... }:
let
    modifier = "SUPER";
    browser = "brave";
    terminal = "ghostty";
in
{
  wayland.windowManager.hyprland.settings = {
    bindd = [
       # Close windows
      "${modifier}, W, Close window, killactive,"

      # Control tiling
      "${modifier}, J, Toggle window split, togglesplit,"
      "${modifier}, P, Pseudo window, pseudo,"
      "${modifier}, T, Toggle window floating/tiling, togglefloating,"
      "${modifier} ALT, F, Full screen, fullscreen, 0"
      "${modifier} CTRL, F, Tiled full screen, fullscreenstate, 0 2"
      "${modifier} ALT, F, Full width, fullscreen, 1"

      # Move focus with ${modifier} + arrow keys
      "${modifier}, LEFT, Move window focus left, movefocus, l"
      "${modifier}, RIGHT, Move window focus right, movefocus, r"
      "${modifier}, UP, Move window focus up, movefocus, u"
      "${modifier}, DOWN, Move window focus down, movefocus, d"

      # Switch workspaces with ${modifier} + [1-9]
      "${modifier}, code:10, Switch to workspace 1, workspace, 1"
      "${modifier}, code:11, Switch to workspace 2, workspace, 2"
      "${modifier}, code:12, Switch to workspace 3, workspace, 3"
      "${modifier}, code:13, Switch to workspace 4, workspace, 4"
      "${modifier}, code:14, Switch to workspace 5, workspace, 5"
      "${modifier}, code:15, Switch to workspace 6, workspace, 6"
      "${modifier}, code:16, Switch to workspace 7, workspace, 7"
      "${modifier}, code:17, Switch to workspace 8, workspace, 8"
      "${modifier}, code:18, Switch to workspace 9, workspace, 9"

      # Move active window to a workspace with ${modifier} + SHIFT + [1-9]
      "${modifier} SHIFT, code:10, Move window to workspace 1, movetoworkspace, 1"
      "${modifier} SHIFT, code:11, Move window to workspace 2, movetoworkspace, 2"
      "${modifier} SHIFT, code:12, Move window to workspace 3, movetoworkspace, 3"
      "${modifier} SHIFT, code:13, Move window to workspace 4, movetoworkspace, 4"
      "${modifier} SHIFT, code:14, Move window to workspace 5, movetoworkspace, 5"
      "${modifier} SHIFT, code:15, Move window to workspace 6, movetoworkspace, 6"
      "${modifier} SHIFT, code:16, Move window to workspace 7, movetoworkspace, 7"
      "${modifier} SHIFT, code:17, Move window to workspace 8, movetoworkspace, 8"
      "${modifier} SHIFT, code:18, Move window to workspace 9, movetoworkspace, 9"

      # Control scratchpad
      "${modifier}, S, Toggle scratchpad, togglespecialworkspace, scratchpad"
      "${modifier} ALT, S, Move window to scratchpad, movetoworkspacesilent, special:scratchpad"

      # TAB between workspaces
      "${modifier}, TAB, Next workspace, workspace, e+1"
      "${modifier} SHIFT, TAB, Previous workspace, workspace, e-1"
      "${modifier} CTRL, TAB, Former workspace, workspace, previous"

      # Swap active window with the one next to it with ${modifier} + SHIFT + arrows
      "${modifier} SHIFT, LEFT, Swap window to the left, swapwindow, l"
      "${modifier} SHIFT, RIGHT, Swap window to the right, swapwindow, r"
      "${modifier} SHIFT, UP, Swap window up, swapwindow, u"
      "${modifier} SHIFT, DOWN, Swap window down, swapwindow, d"

      # Cycle through applications on active workspace
      "ALT, TAB, Cycle to next window, cyclenext"
      "ALT SHIFT, TAB, Cycle to prev window, cyclenext, prev"
      "ALT, TAB, Reveal active window on top, bringactivetotop"
      "ALT SHIFT, TAB, Reveal active window on top, bringactivetotop"

      # Resize active window
      "${modifier}, code:20, Expand window left, resizeactive, -100 0"
      "${modifier}, code:21, Shrink window left, resizeactive, 100 0"
      "${modifier} SHIFT, code:20, Shrink window up, resizeactive, 0 -100"
      "${modifier} SHIFT, code:21, Expand window down, resizeactive, 0 100"

      # Scroll through existing workspaces with ${modifier} + scroll
      "${modifier}, mouse_down, Scroll active workspace forward, workspace, e+1"
      "${modifier}, mouse_up, Scroll active workspace backward, workspace, e-1"

      # Toggle groups
      "${modifier}, G, Toggle window grouping, togglegroup"
      "${modifier} ALT, G, Move active window out of group, moveoutofgroup"

      # Join groups
      "${modifier} ALT, LEFT, Move window to group on left, moveintogroup, l"
      "${modifier} ALT, RIGHT, Move window to group on right, moveintogroup, r"
      "${modifier} ALT, UP, Move window to group on top, moveintogroup, u"
      "${modifier} ALT, DOWN, Move window to group on bottom, moveintogroup, d"

      # Navigate a single set of grouped windows
      "${modifier} ALT, TAB, Next window in group, changegroupactive, f"
      "${modifier} ALT SHIFT, TAB, Previous window in group, changegroupactive, b"

      # Scroll through a set of grouped windows with ${modifier} + ALT + scroll
      "${modifier} ALT, mouse_down, Next window in group, changegroupactive, f"
      "${modifier} ALT, mouse_up, Previous window in group, changegroupactive, b"

      # Activate window in a group by number
      "${modifier} ALT, 1, Switch to group window 1, changegroupactive, 1"
      "${modifier} ALT, 2, Switch to group window 2, changegroupactive, 2"
      "${modifier} ALT, 3, Switch to group window 3, changegroupactive, 3"
      "${modifier} ALT, 4, Switch to group window 4, changegroupactive, 4"
      "${modifier} ALT, 5, Switch to group window 5, changegroupactive, 5"
  ];

    bindmd = [
      "${modifier}, mouse:272, Move window, movewindow"
      "${modifier}, mouse:273, Resize window, resizewindow"
    ];
  };
}

