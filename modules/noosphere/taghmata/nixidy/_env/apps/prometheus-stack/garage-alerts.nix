{...}: let
  namespace = "observability";

  # Every Garage series carries garage_cluster. It is stamped by the two
  # ServiceMonitors in the garage-operator app
  # (_modules/templates/garage-admin-metrics.nix), one per cluster, and it is
  # what every expression below groups on.
  sel = "garage_cluster=~\"garage-main|garage-backup\"";

  # Census series (apps/garage-operator/block-census.nix) restricted to data
  # directories whose PV is still Bound. The scans glob the NAS and the node
  # disks, so a directory left behind by a deleted volume would otherwise drag
  # the minimum down and page forever. `* on (persistentvolume) group_left ()
  # (x == 1)` multiplies by 1 and keeps the census labels.
  bound = metric: ''
    (
      ${metric}{${sel}}
      * on (persistentvolume) group_left ()
      (kube_persistentvolume_status_phase{phase="Bound"} == 1)
    )
  '';
  censusBlocks = bound "garage_census_blocks";
  # Garage's own cluster gauges are per-node views: each storage pod reports
  # what it sees of the whole cluster. min-by-cluster therefore asks "what is
  # the worst view any node has", which is the one that matters. max-by-cluster
  # would let one healthy node hide a broken one.
in {
  # Rule source of truth is a live scrape of both clusters' /metrics (Garage
  # v2.3.0, garage-main-storage-*/garage-backup-storage-* on port 3903), not the
  # upstream docs. Metric names used here, as exported:
  #
  #   cluster_available, cluster_healthy, cluster_connected_nodes,
  #   cluster_known_nodes, cluster_storage_nodes, cluster_storage_nodes_ok,
  #   cluster_partitions, cluster_partitions_quorum, cluster_partitions_all_ok,
  #   garage_replication_factor, garage_local_disk_avail{volume=...},
  #   garage_local_disk_total{volume=...}, block_resync_queue_length,
  #   block_resync_counter, block_resync_errored_blocks, up
  #
  # Deliberately NOT used: the garage-operator chart's own PrometheusRule
  # template (helm values `prometheusRules.enabled`) references
  # `rpc_netapp_request_counter{status="error"}` and `job="garage"`. Garage
  # v2.3.0 exports `rpc_request_counter` and `rpc_netapp_error_counter` instead,
  # so that RPC-error rule can never fire against these clusters, and the chart
  # ships no node-count, quorum or "queue is not draining" rule at all.
  applications.prometheus-grafana.resources.prometheusRules.garage = {
    metadata = {
      inherit namespace;
      # spec.ruleSelector = matchLabels {release = kube-prometheus-stack}.
      labels = {release = "kube-prometheus-stack";};
    };

    spec.groups = [
      {
        name = "garage.cluster";
        rules = [
          {
            alert = "GarageClusterUnavailable";
            expr = "min by (garage_cluster) (cluster_available{${sel}}) == 0";
            "for" = "1m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} is unavailable";
              description = "cluster_available has been 0 for over a minute: the cluster lost quorum and is refusing reads/writes. garage-backup holds every CNPG backup and WAL archive; garage-main backs the Nix binary cache, Harbor blobs and Forgejo attachments.";
            };
          }
          {
            alert = "GarageClusterUnhealthy";
            expr = "min by (garage_cluster) (cluster_healthy{${sel}}) == 0";
            "for" = "3m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} reports unhealthy";
              description = "cluster_healthy has been 0 for over 3 minutes. The cluster still serves requests but is degraded (a node is down or partitions are under-replicated).";
            };
          }
          {
            # "Fewer than 3 connected or healthy nodes for over 5 minutes", with 3
            # read from the cluster itself (garage_replication_factor) rather than
            # hardcoded, so raising spec.replication.factor is one change.
            alert = "GarageStorageNodesMissing";
            expr = ''
              (
                min by (garage_cluster) (cluster_connected_nodes{${sel}})
                <
                min by (garage_cluster) (garage_replication_factor{${sel}})
              )
              or
              (
                min by (garage_cluster) (cluster_storage_nodes_ok{${sel}})
                <
                min by (garage_cluster) (garage_replication_factor{${sel}})
              )
            '';
            "for" = "5m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} has fewer than {{ $value }} storage nodes available";
              description = "cluster_connected_nodes or cluster_storage_nodes_ok has been below garage_replication_factor for over 5 minutes. With replication factor 3 a single missing node still leaves quorum, two missing nodes do not. A planned rollout (the operator replaces storage pods one at a time) will fire this for the duration of the restart.";
            };
          }
          {
            alert = "GaragePartitionsWithoutQuorum";
            expr = ''
              min by (garage_cluster) (cluster_partitions_quorum{${sel}})
              <
              min by (garage_cluster) (cluster_partitions{${sel}})
            '';
            "for" = "5m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} has partitions without quorum";
              description = "cluster_partitions_quorum < cluster_partitions for over 5 minutes: some partitions cannot reach a majority, so objects on them are unreadable or unwritable ({{ $value }} partitions are in quorum out of the cluster total).";
            };
          }
          {
            # Fires before GaragePartitionsWithoutQuorum: replicas are missing but
            # quorum still holds. This is the window where a second node loss
            # turns into data unavailability, so it is worth knowing about.
            alert = "GaragePartitionsUnderReplicated";
            expr = ''
              min by (garage_cluster) (cluster_partitions_all_ok{${sel}})
              <
              min by (garage_cluster) (cluster_partitions{${sel}})
            '';
            "for" = "15m";
            labels = {severity = "warning";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} has under-replicated partitions";
              description = "cluster_partitions_all_ok < cluster_partitions for over 15 minutes: not every partition has all its replicas available, although quorum still holds. Quorum is one node loss away.";
            };
          }
        ];
      }

      {
        name = "garage.scrape";
        rules = [
          {
            alert = "GarageTargetDown";
            expr = "up{${sel}} == 0";
            "for" = "5m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage admin endpoint {{ $labels.pod }} ({{ $labels.garage_cluster }}) is down";
              description = "The scrape of /metrics on the admin port 3903 has failed for over 5 minutes. The node process may be down, or its admin API is unreachable; Garage keeps serving S3 traffic on 3900 in the meantime.";
            };
          }
          {
            # Catches the monitoring itself being broken: if the ServiceMonitor,
            # the admin Service or the labels go away, the targets disappear
            # entirely and `up == 0` never appears for them. 3 = one endpoint per
            # storage pod, which is what the Endpoints objects give today.
            alert = "GarageClusterNotScraped";
            expr = "count by (garage_cluster) (up{${sel}}) < 3";
            "for" = "15m";
            labels = {severity = "warning";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} is not fully scraped";
              description = "Fewer than 3 Garage admin targets are present for this cluster for over 15 minutes ({{ $value }} seen). Either a storage pod is gone, or the ServiceMonitor/Service labels stopped matching and these rules are now blind. Check the Targets page for job=garage-main-admin or job=garage-backup-admin.";
            };
          }
        ];
      }

      {
        name = "garage.storage";
        rules = [
          {
            # garage-backup's data volume is a 300Gi PVC on the shared NFS export
            # (csi-driver-nfs does not quota subdirectories), so its
            # garage_local_disk_total is the whole Synology volume1 (46 TB), not
            # the PVC. garage-main's data and metadata both sit on the same
            # node-local filesystem, so the two `volume` series carry the same
            # numbers: taking the min of the ratio collapses each node to its
            # worst filesystem and de-duplicates that.
            alert = "GarageDiskCapacityHigh";
            expr = ''
              1 -
              min by (garage_cluster, instance, pod, node) (
                garage_local_disk_avail{${sel}}
                /
                garage_local_disk_total{${sel}}
              ) > 0.85
            '';
            "for" = "15m";
            labels = {severity = "warning";};
            annotations = {
              summary = "Garage node {{ $labels.pod }} ({{ $labels.garage_cluster }}) is over 85% full";
              description = "The most-used filesystem on this storage node has been above 85% for over 15 minutes ({{ $value }} used). Garage keeps writing until the disk fills; for garage-backup this is the shared NAS volume, so the threshold covers everything on it.";
            };
          }
          {
            alert = "GarageDiskAlmostFull";
            expr = ''
              1 -
              min by (garage_cluster, instance, pod, node) (
                garage_local_disk_avail{${sel}}
                /
                garage_local_disk_total{${sel}}
              ) > 0.95
            '';
            "for" = "10m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage node {{ $labels.pod }} ({{ $labels.garage_cluster }}) is over 95% full";
              description = "Above 95% used for over 10 minutes ({{ $value }}). Writes start failing and a full metadata volume takes the whole node out of the cluster.";
            };
          }
          {
            alert = "GarageBlockResyncErrors";
            expr = "max by (garage_cluster) (block_resync_errored_blocks{${sel}}) > 0";
            "for" = "10m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} has block resync errors";
              description = "block_resync_errored_blocks has been non-zero for over 10 minutes ({{ $value }} blocks). A block that cannot be resynced is a block whose replicas are unreadable: this is a data-integrity signal, not a throughput one.";
            };
          }
          {
            # "Resync queue not draining for an hour". Both halves are needed:
            # a non-empty queue alone is normal here -- garage-backup has been
            # catching up its third storage node and has held ~8-9 queued blocks
            # while completing resyncs -- and a flat counter alone is normal when
            # there is nothing to do (garage-main's queue is 0 and its counter is
            # idle). Stalled = work pending AND no completed resync in an hour.
            # increase(), not delta(), so a storage pod restart (counters are
            # per-process) does not turn the rule off with a negative delta.
            alert = "GarageResyncQueueStalled";
            expr = ''
              (block_resync_queue_length{${sel}} > 0)
              and
              (increase(block_resync_counter{${sel}}[1h]) < 1)
            '';
            "for" = "10m";
            labels = {severity = "warning";};
            annotations = {
              summary = "Garage node {{ $labels.pod }} ({{ $labels.garage_cluster }}) has a stalled resync queue";
              description = "block_resync_queue_length has been non-empty with fewer than one completed resync in the last hour ({{ $value }} blocks queued). Replica repair is not making progress: check RPC reachability between nodes and disk health on `{{ $labels.node }}`.";
            };
          }
        ];
      }

      {
        name = "garage.bucket";
        rules = [
          {
            # Bucket-level quota numbers come from the OPERATOR's metrics
            # (garage_operator_bucket_*, scraped by the chart's ServiceMonitor
            # in apps/garage-operator once its metrics-reader ClusterRole is
            # bound to Prometheus' ServiceAccount): Garage's own admin
            # /metrics -- everything the groups above read -- exports no
            # per-bucket series. The operator polls each GarageBucket's usage
            # into status.quotaUsage and exports size, limit and the ratio;
            # the ratio exists only for buckets that set a size limit, which
            # today is exactly sccache (100 GiB, 30-day expiry -- sccache
            # never deletes, so the lifecycle rule is the only thing that
            # empties it, and a fill this fast means the rule is not keeping
            # up or something is writing junk). max-by collapses the three
            # operator replicas: only the leader reconciles and sets the
            # gauge, and a stale ex-leader must not mask the current value.
            #
            # The garage_cluster label is stamped statically, not scraped:
            # these series come from the operator, not from a cluster's admin
            # endpoint, and the label is what Alertmanager's ntfy-warning
            # route matches on -- without it a warning falls through to the
            # null receiver.
            alert = "GarageBucketQuotaNearing";
            expr = ''
              max by (namespace, bucket)
                (garage_operator_bucket_quota_size_utilization_ratio{bucket="sccache"})
              > 0.85
            '';
            "for" = "15m";
            labels = {
              severity = "warning";
              garage_cluster = "garage-main";
            };
            annotations = {
              summary = "Garage bucket {{ $labels.bucket }} ({{ $labels.garage_cluster }}) is above 85% of its size quota";
              description = "garage_operator_bucket_quota_size_utilization_ratio has been above 0.85 for over 15 minutes ({{ $value }} of the quota used). The sccache bucket is capped at 100 GiB with objects expiring after 30 days; past the cap, sccache uploads fail and CI/workstation builds fall back to uncached compiles (SCCACHE_IGNORE_SERVER_IO_ERROR keeps them green). Either the churn outgrew the window or the lifecycle worker is not deleting: check the bucket's lifecycle status and consider raising quotas.maxSize or shortening expirationDays.";
            };
          }
        ];
      }

      {
        # Fed by the block census pods, which count block files every 15
        # minutes: one pod reading garage-backup's NFS export, one per machine
        # for garage-main's local disks. These are the only rules that see
        # blocks deleted underneath a running node: Garage's own metrics stayed
        # green for 28 hours after 5250 blocks were removed from
        # data-garage-backup-0 on 2026-11-07. The `for` windows are sized to
        # that 15-minute cadence.
        name = "garage.census";
        rules = [
          {
            # The marker is the canary: it was deleted along with the blocks,
            # and its absence is what makes the node refuse to start. Catching
            # it here means repairing before a restart, not after.
            alert = "GarageDataMarkerMissing";
            expr = "${bound "garage_census_marker_present"} == 0";
            "for" = "1m";
            labels = {severity = "critical";};
            annotations = {
              summary = "Garage data directory {{ $labels.persistentvolumeclaim }} ({{ $labels.garage_cluster }}) has lost its garage-marker";
              description = "The garage-marker file is gone from a live data directory of {{ $labels.garage_cluster }} (on the NAS for garage-backup, on the node's /mnt/storage/garage for garage-main). Something deleted files there. The node keeps running, but the next restart crashloops with `Could not find expected marker file`. Do not restart it: restore the marker (its value is in data_layout in the node's metadata directory, written without a trailing newline), then run `garage repair --yes blocks` on that node and compare its block count with a peer.";
            };
          }
          {
            # Both clusters run replication factor 3 on 3 nodes, so every node
            # holds every block (garage-main: 236,383 on each on 2026-11-09).
            # 1% of garage-backup's ~155k blocks is ~1550; the 2026-11-07
            # deletion was 3.4%. Healthy nodes differ by the handful of blocks written while
            # the scan walks one directory and not yet the next, and a node
            # catching up after downtime converges within the resync window,
            # hence two full scans' worth of `for`.
            alert = "GarageBlockCountDivergence";
            expr = ''
              (
                max by (garage_cluster) (${censusBlocks})
                -
                min by (garage_cluster) (${censusBlocks})
              )
              /
              max by (garage_cluster) (${censusBlocks})
              > 0.01
            '';
            "for" = "40m";
            labels = {severity = "warning";};
            annotations = {
              summary = "Garage cluster {{ $labels.garage_cluster }} nodes hold different numbers of blocks";
              description = "With replication factor 3 every node holds every block, but the nodes' block counts have differed by more than 1% for over 40 minutes ({{ $value | humanizePercentage }} of the largest count). One node is missing blocks: deleted by hand, lost to the filesystem, or still resyncing after downtime. Find the low node with `garage_census_blocks`, then run `garage repair --yes blocks` on it.";
            };
          }
          {
            # Without this, a dead census would silently turn the two rules
            # above off. min, not max: garage-main has one census pod per
            # machine and the oldest scan is the one that matters. absent()
            # keeps its equality matcher as a label, so each cluster's term
            # still carries garage_cluster and routes like every Garage warning.
            alert = "GarageBlockCensusIncomplete";
            expr = ''
              (time() - min by (garage_cluster) (garage_census_last_scan_timestamp_seconds{${sel}}) > 3600)
              or
              absent(garage_census_last_scan_timestamp_seconds{garage_cluster="garage-backup"})
              or
              absent(garage_census_last_scan_timestamp_seconds{garage_cluster="garage-main"})
              or
              (count by (garage_cluster) (${censusBlocks}) < 3)
            '';
            "for" = "40m";
            labels = {severity = "warning";};
            annotations = {
              summary = "The {{ $labels.garage_cluster }} block census is stale or missing a node";
              description = "The census (garage-operator/garage-backup-block-census, or the garage-main-block-census DaemonSet) has not finished a scan in over an hour, or has fewer than 3 live data directories to report. While this fires, missing blocks and missing markers go undetected. Check the pod's logs and the garage_census_scan_error series; a directory whose scan fails is left out instead of being reported with a partial count.";
            };
          }
        ];
      }
    ];
  };
}
