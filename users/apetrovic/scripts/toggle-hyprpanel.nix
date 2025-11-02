{ pkgs, lib, ...}:
let
  hyprpanel-toggle = pkgs.writeShellScriptBin "hyprpanel-toggle" /*bash*/ ''
    #!usr/bin/env bash
    set -euo pipefail

    PGREP="${lib.getExe pkgs.procps}/pgrep"
    HYPRPANEL="${lib.getExe' pkgs.hyprpanel "hyprpanel"}"

    if "$PGREP" -x hyprpanel >/dev/null 2>&1; then
      exec "$HYPRPANEL" -q
    else
      # start detached so keybind doesn't block
      nohup "$HYPRPANEL" >/dev/null 2>&1 &
    fi
    
  '';
in
{
  home.packages = [ hyprpanel-toggle ];
}
