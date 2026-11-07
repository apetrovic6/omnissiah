# cerberus pings its own external dead man's switch every minute.
#
# The cluster's Alertmanager pages through ntfy, and ntfy runs here. So when
# cerberus is down, CerberusTargetDown fires in the cluster but has nowhere to go,
# and the Alertmanager heartbeat (kube-secrets/alertmanager) stays green because
# the cluster itself is fine. This closes that gap from the other side: cerberus
# hits a healthchecks.io check of its own, and healthchecks.io emails when the
# pings stop. Nothing on the way depends on ntfy or the cluster.
#
# A missing ping means any of: cerberus is down or hung, its uplink is gone, or
# its own DNS (Technitium, which this host resolves through) can't answer for
# hc-ping.com. All three are worth an email, since the whole LAN resolves through
# this box.
#
# The ping URL is a credential (anyone holding it can mark the check healthy), so
# it lives in a clan var and reaches the unit through LoadCredential, never the
# nix store. Create the check first (period 1 minute, grace 5 minutes, email
# integration, NOT ntfy), then store its URL with
#   clan vars generate cerberus --generator cerberus-heartbeat
# Until that has run, deploys stop at this prompt.
{
  config,
  pkgs,
  ...
}: let
  generatorName = "cerberus-heartbeat";
in {
  clan.core.vars.generators.${generatorName} = {
    prompts.url = {
      description = "Ping URL of cerberus' own healthchecks.io check (https://hc-ping.com/<uuid>, period 1 minute, grace 5 minutes)";
      type = "hidden";
      persist = true;
    };

    # Root-owned: systemd reads it for LoadCredential, the DynamicUser never
    # opens the original.
    files.url.secret = true;

    runtimeInputs = [pkgs.coreutils];

    script = ''
      set -euo pipefail

      # Strip stray whitespace from the paste; a trailing newline inside the
      # curl config line below would end the URL early.
      url="$(tr -d '[:space:]' < "$prompts/url")"

      case "$url" in
        https://*) ;;
        *)
          echo "cerberus-heartbeat: expected an https:// ping URL" >&2
          exit 1
          ;;
      esac

      printf '%s' "$url" > "$out/url"
    '';
  };

  systemd.services.cerberus-heartbeat = {
    description = "Ping cerberus' external dead man's switch";
    wants = ["network-online.target"];
    after = ["network-online.target"];

    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      LoadCredential = ["url:${config.clan.core.vars.generators.${generatorName}.files.url.path}"];
    };

    # The URL goes to curl through a config on stdin rather than argv, so it
    # never shows up in `ps` or the journal. --retry covers a single dropped
    # packet; a minute of real silence is what the check is for.
    script = ''
      printf 'url = "%s"\n' "$(cat "$CREDENTIALS_DIRECTORY/url")" \
        | ${pkgs.curl}/bin/curl --config - \
            --fail --silent --show-error --output /dev/null \
            --max-time 10 --retry 3
    '';
  };

  systemd.timers.cerberus-heartbeat = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      # The check allows 5 minutes of grace, so a few seconds of drift is free
      # and lets systemd batch wakeups.
      AccuracySec = "10s";
    };
  };
}
