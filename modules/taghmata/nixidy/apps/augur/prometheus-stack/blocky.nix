# Monitoring for Blocky, the LAN's DNS resolver (modules/rites/blocky.nix): a
# ScrapeConfig per resolver, the alerts, and Blocky's Grafana dashboard.
#
# The resolvers are read from cartographa's `lan.resolvers` (addresses), and
# mapped back to host names through `cartographa.hosts`. A host added to
# `lan.resolvers` is scraped and alerted on with nothing to write here, as
# long as it runs the blocky module (which then opens the metrics proxy).
#
# Where the series come from: Blocky's own /metrics, reached through the
# metrics-only proxy each host runs on `proxyPort`, which admits the k8s nodes
# (the Prometheus pod's scrape leaves through one) and serves nothing but
# GET /metrics: Blocky's HTTP port is its whole unauthenticated REST API.
#
# Why a ScrapeConfig, the labels, and the `instance` relabel: see ./nodes.nix,
# which this follows; the reasoning is the same and not repeated.
{...}: {
  nixidy.envs.prod.apps.prometheus-blocky = {
    cartographa,
    lib,
    ...
  }: let
    namespace = "observability";
    # services.imperium.blocky.metricsProxy.port (modules/rites/blocky.nix).
    proxyPort = 4001;

    hostOf = address: let
      names = builtins.filter (n: cartographa.hosts.${n} == address) (builtins.attrNames cartographa.hosts);
    in
      assert lib.assertMsg (names != []) "lan.resolvers entry ${address} is not in cartographa.hosts";
        builtins.head names;
    resolvers = map hostOf cartographa.lan.resolvers;

    jobName = host: "${host}-blocky";
    blockyJobs = lib.concatMapStringsSep "|" jobName resolvers;
    sel = ''job=~"${blockyJobs}"'';

    # Node-exporter jobs of the resolvers (./nodes.nix: `<host>-node`), minus
    # cerberus: ./cerberus-alerts.nix already pages on ANY failed unit there,
    # and a second alert for the same unit would page twice.
    nodeJobs = lib.concatMapStringsSep "|" (h: "${h}-node") (builtins.filter (h: h != "cerberus") resolvers);

    # Warnings with this label go to the phone (the second severity=warning
    # route in ./default.nix; same mechanism as cerberus-alerts.nix). Every
    # rule here is rare and means a resolver is degraded, so they all page.
    warn = {
      severity = "warning";
      notify = "phone";
    };

    # Denylist size, per Blocky denylist group (modules/rites/blocky.nix keeps
    # the ad lists and the NRD list in separate groups, so one cannot hide the
    # other failing). `min` is the alert threshold in entries.
    #
    # ads: StevenBlack + hagezi pro.plus + native.apple are about 0.4M together
    # (about 3.4M in all, of which nrd7 is about 3.0M, per the figures in
    # modules/rites/blocky.nix). 300k is about a quarter below that: it catches
    # losing hagezi pro.plus, the bulk of them, or all three, but NOT losing only
    # StevenBlack or native.apple (tens of thousands each); a failed download
    # of those shows in blocky_failed_downloads_total instead.
    # nrd: nrd7 is about 3.0M and moves with the week's registrations; 2.0M is a
    # third below, far outside that movement, and a lost file reads 0.
    denylistGroups = {
      ads = 300000;
      nrd = 2000000;
    };
    denylistRules = lib.concatLists (lib.mapAttrsToList (group: min: [
        {
          alert = "BlockyDenylist${lib.toUpper (builtins.substring 0 1 group)}${builtins.substring 1 (-1) group}TooSmall";
          expr = ''sum by (instance, host) (blocky_denylist_cache_entries{${sel},group="${group}"}) < ${toString min}'';
          "for" = "30m";
          labels = warn;
          annotations = {
            summary = "Blocky {{ $labels.host }} has a suspiciously small ${group} denylist";
            description = "The ${group} denylist group has {{ $value }} entries on {{ $labels.host }} (alert below ${toString min}; 30 minutes, since servitor loads its lists for a while after every restart). Its lists failed to download or parse and no cached copy was used, so those names are being answered normally. Check `journalctl -u blocky` on {{ $labels.host }} for download errors, `blocky_failed_downloads_total` in the Blocky dashboard${lib.optionalString (group == "nrd") ", and `blocky-nrd.service` (the list is converted into /var/lib/blocky-nrd)"}.";
          };
        }
        {
          # No series at all while the host is up: no value to quote.
          alert = "BlockyDenylist${lib.toUpper (builtins.substring 0 1 group)}${builtins.substring 1 (-1) group}Missing";
          expr = ''up{${sel}} == 1 unless on (instance) blocky_denylist_cache_entries{group="${group}"}'';
          "for" = "30m";
          labels = warn;
          annotations = {
            summary = "Blocky {{ $labels.host }} reports no ${group} denylist";
            description = "Blocky on {{ $labels.host }} is up but exports no blocky_denylist_cache_entries for the ${group} group: the group is not configured or its lists never loaded. Check `journalctl -u blocky` on the host and the denylists in modules/rites/blocky.nix.";
          };
        }
      ])
      denylistGroups);

    # Series are per instance; the ScrapeConfig below stamps instance=<host>.
    ruleSet = name: rules: {
      inherit name;
      inherit rules;
    };
  in {
    applications.prometheus-grafana.resources.scrapeConfigs = builtins.listToAttrs (map (host: {
        name = jobName host;
        value = {
          metadata = {
            inherit namespace;
            # Load-bearing: spec.scrapeConfigSelector (see ./nodes.nix).
            labels = {release = "kube-prometheus-stack";};
          };
          spec = {
            jobName = jobName host;
            scrapeInterval = "30s";
            scrapeTimeout = "10s";
            scheme = "http";
            metricsPath = "/metrics";
            staticConfigs = [
              {
                targets = ["${cartographa.hosts.${host}}:${toString proxyPort}"];
                labels = {inherit host;};
              }
            ];
            relabelings = [
              {
                action = "replace";
                sourceLabels = ["__address__"];
                regex = ".*";
                replacement = host;
                targetLabel = "instance";
              }
            ];
          };
        };
      })
      resolvers);

    applications.prometheus-grafana.resources.prometheusRules.blocky = {
      metadata = {
        inherit namespace;
        labels = {release = "kube-prometheus-stack";};
      };
      spec.groups = [
        (ruleSet "blocky.availability" [
          {
            alert = "BlockyInstanceDown";
            expr = ''up{${sel}} == 0'';
            "for" = "5m";
            labels = warn;
            annotations = {
              summary = "Blocky on {{ $labels.host }} is not answering its metrics scrape";
              description = "The scrape of {{ $labels.host }}:${toString proxyPort} has failed for over 5 minutes. Clients fail over to the other resolvers, so DNS still works but redundancy is gone. Check, in order: the host is up; `systemctl status blocky blocky-metrics-proxy` on it; its firewall admits the k8s node the Prometheus pod runs on (modules/rites/blocky.nix, metricsProxy.sources). If only this alert fires and `dig @{{ $labels.host }}` works, it is the proxy or the firewall, not DNS.";
            };
          }
          {
            # Not `count(up == 0) == N`: that is silent when the series vanish.
            alert = "BlockyAllInstancesDown";
            expr = ''(sum(up{${sel}} == 1) or vector(0)) == 0'';
            "for" = "2m";
            labels = {severity = "critical";};
            annotations = {
              summary = "No Blocky resolver is answering its metrics scrape";
              description = "None of ${lib.concatStringsSep ", " resolvers} has been scraped successfully for 2 minutes. Either all three resolvers are down (the LAN has no DNS: check `dig @${builtins.head cartographa.lan.resolvers} example.org` from a LAN machine) or the scrape path is broken for all of them (the cluster node the Prometheus pod runs on, the ScrapeConfigs blocky jobs in observability, the targets page). Clients that fail over still resolve through whichever instance is up.";
            };
          }
        ])
        (ruleSet "blocky.health" ([
            {
              alert = "BlockyBlockingDisabled";
              expr = ''blocky_blocking_enabled{${sel}} == 0'';
              "for" = "30m";
              labels = warn;
              annotations = {
                summary = "Blocking is disabled on Blocky {{ $labels.host }}";
                description = "blocky_blocking_enabled has been 0 for 30 minutes: ads and newly registered domains are being answered normally on {{ $labels.host }}. Someone called /api/blocking/disable, which has a duration and re-enables by itself, so a long disable means it was given none or was re-sent. Re-enable on the host: `curl -X GET http://127.0.0.1:4000/api/blocking/enable` (the API listens on localhost only), or restart blocky.service.";
              };
            }
          ]
          ++ denylistRules))
        (ruleSet "blocky.units" [
          {
            # Per unit, so the alert says which. The node exporter's systemd
            # collector is on for every base machine (modules/rites/node-exporter.nix).
            alert = "BlockyHelperUnitFailed";
            expr = ''node_systemd_unit_state{job=~"${nodeJobs}",name=~"blocky-(querylog-watchdog|nrd)[.]service",state="failed"} == 1'';
            "for" = "5m";
            labels = warn;
            annotations = {
              summary = "{{ $labels.name }} is failed on {{ $labels.instance }}";
              description = "blocky-nrd.service failing means the newly-registered-domains list is stale (the previous file is kept); blocky-querylog-watchdog.service failing is deliberate when Postgres refused Blocky's login (a wrong password or missing role, SQLSTATE 28/3D): the query log is on the journal fallback and a restart will not fix it. Read `journalctl -u {{ $labels.name }}` on the host, fix the cause, then `systemctl reset-failed {{ $labels.name }}`. (cerberus is covered by CerberusSystemdUnitFailed.)";
            };
          }
        ])
      ];
    };

    # Blocky's own dashboard (docs/blocky-grafana.json of the pinned source),
    # picked up by the Grafana dashboard sidecar (label grafana_dashboard, as
    # the garage-operator and cloudnative-pg apps do). Changes against upstream,
    # made with jq: the `__inputs`/`__requires` import placeholders removed (the
    # `DS_PROMETHEUS` datasource template variable stays and resolves to the
    # default Prometheus datasource); the "Blocking control" canvas panel
    # removed, together with its `blocky_url` variable, since its buttons call
    # Blocky's API, which is deliberately not reachable from Grafana; the
    # neighbouring "Failed list downloads" stat widened into the gap.
    applications.prometheus-grafana.resources.configMaps.blocky-grafana-dashboard = {
      metadata = {
        inherit namespace;
        labels.grafana_dashboard = "1";
      };
      data."blocky.json" = builtins.toJSON (builtins.fromJSON (builtins.readFile ./blocky-dashboard.json));
    };
  };
}
