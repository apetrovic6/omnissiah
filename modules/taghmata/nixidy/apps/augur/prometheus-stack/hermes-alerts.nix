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
                summary = "The Hermes work profile has no usable DevZero token";
                description = "hermes-work-token.service has been failed on {{ $labels.instance }} for 10 minutes. The gateway is still up, so default, coder and the app work, but the work rooms and the work profile fail with an auth error until this is fixed. `journalctl -u hermes-work-token` on ryza names the problem: a missing, empty or malformed token file, or an Anthropic credential in the root auth.json (`sudo -iu hermes hermes -p default auth list anthropic`) that the work profile would borrow. Fix: run `claude-as devzero setup-token` on the PC, `clan vars generate ryza --generator hermes-work-claude-token --regenerate`, deploy ryza, then `systemctl restart hermes-gateway hermes-dashboard` (a deploy rewrites the dotenv but restarts neither), and `systemctl start hermes-work-token` to clear the alert.";
              };
            }
          ];
        }
      ];
    };
  };
}
