{...}: let
  namespace = "observability";

  # Every series below comes from the ScrapeConfig in ./cerberus-scrape.nix:
  #   job="cerberus-node", instance="cerberus", host="cerberus"
  jobName = "cerberus-node";
  target = "192.168.1.105:9100";
  sel = ''job="${jobName}"'';

  # The filesystems that actually hold data on this host.
  #
  # cerberus has one disk and one data partition (machines/cerberus/disko.nix:
  # a 500M vfat ESP at /boot and a 100%-of-remainder ext4 at /), so today this
  # matches exactly one mountpoint: /. /var/lib is NOT a separate mount, so the
  # "same rule for /var/lib" question in the brief has no separate mount to apply
  # to — /var/lib is inside /, which is also why the 2026-11-06 98% event was a
  # root-disk event.
  #
  # Keyed on fstype instead of mountpoint="/" on purpose: if the disk is ever
  # re-laid out (a separate /var/lib, or btrfs/xfs instead of ext4) the rules keep
  # covering it without an edit, and $labels.mountpoint in the annotation says
  # which mount is in trouble. It also excludes, on purpose:
  #   - vfat /boot (500 MiB, holds kernels/bootspec; alerting at 85% there is
  #     noise today and would need its own threshold),
  #   - tmpfs/ramfs (node_exporter 1.12.1 does NOT exclude tmpfs by default, so
  #     they are scraped; they are not capacity),
  #   - NFS/SMB (excluded from the collector entirely in machines/cerberus/
  #     monitoring.nix).
  localFs = ''fstype=~"ext4|btrfs|xfs"'';

  # Warnings that carry this label are routed to the phone by the second
  # severity=warning route in default.nix. It is the general mechanism, not a
  # cerberus-specific hack: any future rule whose warning must page declares it
  # here instead of borrowing someone else's label. Garage warnings keep routing
  # through their own `garage_cluster != ""` route and are untouched.
  pageLabels = {
    severity = "warning";
    notify = "phone";
  };
in {
  # Metric names and label names are from a live scrape, not memory: the pinned
  # node_exporter 1.12.1 (same build as the cluster's DaemonSet — the chart's
  # node-exporter reports version="1.12.1" in node_exporter_build_info) was run with
  # the flags machines/cerberus/monitoring.nix sets, and /metrics was read:
  #
  #   node_filesystem_avail_bytes{device,device_error,fstype,mountpoint}
  #   node_filesystem_size_bytes{device,device_error,fstype,mountpoint}
  #   node_filesystem_readonly{...}
  #   node_systemd_unit_state{name,state,type}      state="failed" is one of
  #                                                 activating|active|deactivating|
  #                                                 failed|inactive
  #   node_systemd_units{state}                     aggregate counts
  #   node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
  #   up{job,...}
  #
  # Worth knowing: 1.12.1 exports the mount label as `mountpoint`, not
  # `mount_point` — which is also what the chart's own node rules use. A rule
  # written against `mount_point` matches nothing and reports "all quiet".
  #
  # `node_systemd_unit_state` emits one series per (unit, state) and the value is
  # 0 or 1, so the failed-unit rule has to compare `== 1`; a bare selector would
  # alert on the zero-valued siblings of the same unit.
  applications.prometheus-grafana.resources.prometheusRules.cerberus = {
    metadata = {
      inherit namespace;
      # spec.ruleSelector = matchLabels {release = kube-prometheus-stack}.
      labels = {release = "kube-prometheus-stack";};
    };

    spec.groups = [
      {
        name = "cerberus.availability";
        rules = [
          {
            # The scrape itself is the liveness check: if the exporter stops, the
            # host is down, or something between the cluster and cerberus broke,
            # `up` goes to 0 and stays there. 3 minutes rather than the 5-10m the
            # chart uses for cluster targets because the blast radius is different:
            # cerberus is the LAN's only DNS server (Technitium here, and every host
            # in the lab points at 192.168.1.105), so while it is down nothing on
            # the LAN resolves anything.
            #
            # Deliberately not `up{job="node-exporter"}`-style 10m and not a ratio:
            # this is one target, and it is either reachable or it is not.
            alert = "CerberusTargetDown";
            expr = ''up{${sel}} == 0'';
            "for" = "3m";
            labels = {severity = "critical";};
            annotations = {
              summary = "cerberus is not answering its metrics scrape";
              description = "The scrape of ${target} has failed for over 3 minutes. Either the host is down, prometheus-node-exporter.service is not running, or the four node-IP firewall rules no longer match the node the Prometheus pod is on. When cerberus is down the LAN has no DNS (Technitium runs here) and Forgejo, ntfy, immich, Plex and Postgres go with it.";
            };
          }
          {
            # The other half of "cerberus is down": the failure of the monitoring
            # rather than of the host. If the ScrapeConfig is deleted, the labels
            # stop matching, or the job is renamed, the target disappears from the
            # configuration entirely and `up == 0` never appears for it — a rule
            # that only looks at up==0 goes silent exactly when the monitoring
            # breaks, which is the failure mode 2026-11-06 actually had (no signal
            # at all).
            alert = "CerberusTargetAbsent";
            expr = ''absent(up{${sel}})'';
            "for" = "3m";
            labels = {severity = "critical";};
            annotations = {
              summary = "cerberus is not being scraped at all";
              description = "No target for job=${jobName} exists in the Prometheus configuration for over 3 minutes. The target is not failing — it is missing: check the ScrapeConfig cerberus-node in observability, its release label, and the Targets page.";
            };
          }
        ];
      }

      {
        name = "cerberus.storage";
        rules = [
          {
            alert = "CerberusFilesystemHighUsage";
            expr = ''
              1 - (
                node_filesystem_avail_bytes{${sel},${localFs}}
                /
                node_filesystem_size_bytes{${sel},${localFs}}
              ) > 0.85
            '';
            "for" = "15m";
            labels = pageLabels;
            annotations = {
              summary = "cerberus filesystem {{ $labels.mountpoint }} is over 85% full";
              description = "Used has been above 85% for over 15 minutes ({{ $value | humanizePercentage }} used on {{ $labels.mountpoint }}, device {{ $labels.device }}). This is the level where a single runaway writer stops being survivable: the 2026-11-06 event reached 98% on a 125 GiB root because of one stale 50 GiB container volume, and nothing was watching. First suspects: nix store/gc margins (min-free=20GiB in configuration.nix), runner workspaces, /var/lib container volumes.";
            };
          }
          {
            # No `notify` label: severity=critical already routes to ntfy-critical.
            alert = "CerberusFilesystemAlmostFull";
            expr = ''
              1 - (
                node_filesystem_avail_bytes{${sel},${localFs}}
                /
                node_filesystem_size_bytes{${sel},${localFs}}
              ) > 0.95
            '';
            "for" = "10m";
            labels = {severity = "critical";};
            annotations = {
              summary = "cerberus filesystem {{ $labels.mountpoint }} is over 95% full";
              description = "Used has been above 95% for over 10 minutes ({{ $value | humanizePercentage }}). At this level Postgres, Forgejo and the nix daemon start failing writes, and a CI job failing 'mysteriously' is usually the first visible symptom — that was the only signal during the 2026-11-06 event.";
            };
          }
          {
            # "It will be full within 24h", independent of how full it is right now:
            # the 85%/95% pair only notices a fill once the disk is already in the
            # bad zone, and by then the interesting part (what wrote) has had hours
            # to cover its tracks. This one fires on the slope.
            #
            # Three guards, all needed:
            #   - avail/total < 0.20 keeps a big one-off write on a mostly-empty
            #     disk (a fresh Nix build, a generation swap) from predicting a full
            #     disk; predict_linear extrapolates whatever it is given.
            #   - predict_linear(...[6h], 24*60*60) < 0 is the 24h projection. 6h is
            #     long enough to average out a build burst and short enough to catch
            #     a volume filling now; it needs ~6h of history to be useful, so a
            #     freshly-restarted Prometheus cannot evaluate it for its first
            #     hours (Prometheus retains 30d, so that is only true right after a
            #     TSDB wipe).
            #   - readonly == 0: a read-only mount returns a flat avail, and a flat
            #     series has slope 0, so the predictor would be talking about a disk
            #     that cannot fill at all.
            alert = "CerberusFilesystemSpaceFillingUp";
            expr = ''
              (
                node_filesystem_avail_bytes{${sel},${localFs}}
                /
                node_filesystem_size_bytes{${sel},${localFs}} < 0.20
              )
              and
              (
                predict_linear(node_filesystem_avail_bytes{${sel},${localFs}}[6h], 24*60*60) < 0
              )
              and
              (
                node_filesystem_readonly{${sel},${localFs}} == 0
              )
            '';
            "for" = "30m";
            labels = pageLabels;
            annotations = {
              summary = "cerberus filesystem {{ $labels.mountpoint }} is predicted to fill within 24 hours";
              description = "predict_linear over 6h projects node_filesystem_avail_bytes on {{ $labels.mountpoint }} crossing zero within the next 24 hours while available is already under 20% (available now: {{ $value | humanizePercentage }} of the filesystem). Find the writer before it fills: nix store growth against min-free/max-free, runner job workspaces, container volumes, journal growth.";
            };
          }
        ];
      }

      {
        name = "cerberus.system";
        rules = [
          {
            # One alert per failed unit ($labels.name is in the message), rather
            # than node_systemd_units{state="failed"} > 0, because "one unit is
            # failed" is only actionable if it says which one — and a unit that is
            # failed stays failed until `systemctl reset-failed`, so this alert
            # firing for hours is the honest state of the machine, not flapping.
            #
            # 5 minutes: long enough to skip a restart that clears itself (a unit
            # failing once because a dependency was still mounting), short enough to
            # beat the point where a dead Forgejo/Technitium/ntfy unit becomes an
            # outage someone else notices first.
            alert = "CerberusSystemdUnitFailed";
            expr = ''node_systemd_unit_state{${sel},state="failed"} == 1'';
            "for" = "5m";
            labels = pageLabels;
            annotations = {
              summary = "systemd unit {{ $labels.name }} is failed on cerberus";
              description = "node_systemd_unit_state{name={{ $labels.name }},state=failed} has been 1 for over 5 minutes (unit type {{ $labels.type }}). Failed units persist until `systemctl reset-failed`, so check the unit and then reset it. Mount units are deliberately included (Forgejo stateDir and immich media live on /mnt/nas); .automount/.device/.scope/.slice units are excluded by the exporter's unit filter.";
            };
          }
          {
            # Ratio, not an absolute floor, so the threshold means the same thing
            # whatever RAM this VM is given. 10% available for 15 minutes is the
            # point where the next big allocation (immich's ML model, Plex
            # transcode, a Postgres sort, a Forgejo GC) is the one that tips it into
            # the OOM killer, and the OOM killer on this host picks the biggest
            # thing running rather than the thing that just grew.
            #
            # MemAvailable (not MemFree) is the right gauge: it counts reclaimable
            # page cache, and on a file server most of "free" memory is cache that
            # can be handed back.
            #
            # No swap rule: no swap is configured on this host, so there is nothing
            # to measure, and a rule that can never fire is noise on paper.
            alert = "CerberusMemoryPressure";
            expr = ''
              node_memory_MemAvailable_bytes{${sel}}
              /
              node_memory_MemTotal_bytes{${sel}} < 0.10
            '';
            "for" = "15m";
            labels = pageLabels;
            annotations = {
              summary = "cerberus has been low on available memory for 15 minutes";
              description = "node_memory_MemAvailable_bytes has been under 10% of node_memory_MemTotal_bytes for over 15 minutes ({{ $value | humanizePercentage }} available). Sustained pressure here means the OOM killer is next, and on this host that means Postgres or Forgejo. Check immich's ML worker, Plex transcodes, HA and the runner's builds.";
            };
          }
        ];
      }
    ];
  };
}
