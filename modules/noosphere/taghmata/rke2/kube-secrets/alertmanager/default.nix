# Dead man's switch for the alerting pipeline: the URL of the external heartbeat.
#
# `Watchdog` is `expr: vector(1)` -- it fires on every evaluation, by design. That
# makes it the one alert whose *absence* is the signal: route it to an outside
# service that complains when the pings stop, and that service is the only thing
# noticing when Alertmanager, Prometheus, the cluster, the network or the lab's
# power are down together. Everything else in this repo pages on a problem; this
# pages on the pager being dead.
#
# The check itself is external and cannot be minted here: create it first (any
# healthchecks.io-style "expect a ping every N minutes, alert when it stops"
# service), then store its ping URL with
#   clan vars generate cerberus --generator alertmanager-heartbeat
# which prompts for the URL and persists it in the sops secret store. The URL is a
# credential -- anyone who has it can mark the check as OK -- so it lives in a var,
# not in a manifest: Alertmanager reads it from
# /etc/alertmanager/secrets/alertmanager-heartbeat/url via `url_file`.
#
# One output:
#   - alertmanager-heartbeat (non-secret) sops-encrypted SopsSecret in observability,
#     read into the prometheus-grafana app with builtins.readFile.
#
# Until the var exists there is no value to render, so
# nixidy/_env/apps/prometheus-stack/default.nix skips the heartbeat receiver and
# Watchdog keeps falling through to the `null` receiver instead of referencing a
# file that does not exist (which would make Alertmanager reject its whole config).
# The repo renders either way -- verified: the committed prod manifests build without
# it and contain no heartbeat receiver.
#
# One consequence of committing a prompt-based generator with the var not yet
# generated: `clan vars generate` without --generator (which a machine deploy may run
# for you) will stop at this prompt. Generate it once, early, and everything after is
# automatic like the other prompt-based generators in this repo (pharos/caddy,
# pharos/pangolin, scriptorium/forgejo).
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  generatorName = "alertmanager-heartbeat";
  secretName = "alertmanager-heartbeat";
  namespace = "observability";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${generatorName} = {
      share = true;

      files.${secretName}.secret = false;

      prompts.url = {
        description = "Ping URL of the external dead man's switch (the full https://hc-ping.com/<uuid> URL of the healthchecks.io check, period 1 minute, grace 5 minutes)";
        type = "hidden";
        persist = true;
      };

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        url="$(cat "$prompts/url")"

        # Trim accidental whitespace: url_file contents are used nearly verbatim and
        # a trailing space inside a URL is a 400 waiting to happen. (sops strips
        # leading/trailing whitespace from url_file contents itself; the URL here is
        # what gets stored, so fix it at the source too.)
        url="$(printf '%s' "$url" | tr -d '[:space:]')"

        if [ -z "$url" ]; then
          echo "alertmanager-heartbeat: empty URL; create the external check first" >&2
          exit 1
        fi

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretName}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${secretName}
          namespace: ${namespace}
        spec:
          secretTemplates:
            - name: ${secretName}
              type: Opaque
              stringData:
                url: "$url"
        EOF
      '';
    };
  };
}
