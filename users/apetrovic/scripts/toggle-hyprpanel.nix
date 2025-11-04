{ pkgs, lib, ...}:
let
  hyprpanel-toggle = pkgs.writers.writeBashBin "hyprpanel-toggle" { } /*bash*/ ''
    #!/usr/bin/env bash
    set -euo pipefail

    have_systemd_unit() {
      command -v systemctl >/dev/null 2>&1 || return 1
      systemctl --user list-unit-files hyprpanel.service >/dev/null 2>&1
    }

    is_active_systemd() {
      systemctl --user is-active --quiet hyprpanel.service 2>/dev/null
    }

    is_running_process() {
      # Any of these succeeding counts as "running"
      pidof hyprpanel >/dev/null 2>&1 && return 0
      pgrep -x hyprpanel >/dev/null 2>&1 && return 0
      pgrep -f '(^|[ /])hyprpanel( |$)' >/dev/null 2>&1 && return 0
      return 1
    }

    start_direct() {
      nohup hyprpanel >/dev/null 2>&1 & disown
    }

    if have_systemd_unit; then
      if is_active_systemd; then
        # Toggle off
        systemctl --user stop hyprpanel.service
      else
        # Toggle on
        systemctl --user start hyprpanel.service
      fi
      exit 0
    fi

    # No systemd unit: manage the process ourselves
    if is_running_process; then
      exec hyprpanel -q
    else
      start_direct
    fi
  '';
in
{
  home.packages = [ hyprpanel-toggle ];
}
