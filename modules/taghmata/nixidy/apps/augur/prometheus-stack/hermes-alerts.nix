# Alerts for the Hermes agent on ryza (modules/rites/hermes.nix).
#
# hermes-work-token.service fails when the DevZero token for the work profile
# is missing, empty, malformed, or would be shadowed by a personal Anthropic
# credential in the root auth.json. The gateway deliberately starts anyway
# (default, coder and the app keep working; work's rooms error instead), so a
# failed unit is the only signal, and this is what carries it to the phone.
#
# The series comes from ryza's node exporter (systemd collector, on for every
# `base` machine, modules/rites/node-exporter.nix; its unit filter excludes only
# automount/device/scope/slice units, so a .service is exported) through the
# `ryza-node` ScrapeConfig that ./nodes.nix generates.
{...}: {
  nixidy.envs.prod.apps.prometheus-hermes-alerts = {...}: let
    namespace = "observability";
  in {
    applications.prometheus-grafana.resources.prometheusRules.hermes = {
      metadata = {
        inherit namespace;
        # spec.ruleSelector = matchLabels {release = kube-prometheus-stack}.
        labels = {release = "kube-prometheus-stack";};
      };
      spec.groups = [
        {
          name = "hermes.units";
          rules = [
            {
              alert = "HermesWorkTokenUnitFailed";
              expr = ''node_systemd_unit_state{job="ryza-node",name="hermes-work-token.service",state="failed"} == 1'';
              # The unit re-runs every 15 minutes and on each switch, so a failed
              # run can pass through `activating` for an instant at a scrape.
              "for" = "10m";
              # `notify: phone` routes a warning to ntfy (the second severity=warning
              # route in ./default.nix, same as ./cerberus-alerts.nix and ./blocky.nix).
              labels = {
                severity = "warning";
                notify = "phone";
              };
              annotations = {
                summary = "The Hermes work profile's DevZero token check is failing";
                description = "hermes-work-token.service has been failed on {{ $labels.instance }} for 10 minutes. The gateway is still up, so default, coder and the app work. `journalctl -u hermes-work-token` on ryza says which of two cases this is. (1) The token is missing, empty or malformed, or the work dotenv does not hold it: the work rooms and the work profile answer with an auth error. Fix: run `claude-as devzero setup-token` on the PC, `clan vars generate ryza --generator hermes-work-claude-token --regenerate`, deploy ryza, `systemctl restart hermes-gateway hermes-dashboard` (a deploy rewrites the dotenv but restarts neither), then `systemctl start hermes-work-token`. (2) The message says work is BILLING A PERSONAL CREDENTIAL: the root auth.json has an Anthropic source other than claude_code or env:*, which work borrows and which outranks its token, so it keeps answering on the personal account and a new token does not help. Fix: `sudo -iu hermes hermes -p default auth list anthropic`, then `hermes -p default auth remove anthropic <id>` for that row (or stop the work rooms), then `systemctl start hermes-work-token`.";
              };
            }
          ];
        }
      ];
    };
  };
}
