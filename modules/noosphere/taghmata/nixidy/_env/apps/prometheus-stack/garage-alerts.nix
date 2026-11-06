{...}: let
  namespace = "observability";

  # Every Garage series carries garage_cluster. It is stamped by the two
  # ServiceMonitors in the garage-operator app
  # (_modules/templates/garage-admin-metrics.nix), one per cluster, and it is
  # what every expression below groups on.
  sel = "garage_cluster=~\"garage-main|garage-backup\"";

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
    ];
  };
}
