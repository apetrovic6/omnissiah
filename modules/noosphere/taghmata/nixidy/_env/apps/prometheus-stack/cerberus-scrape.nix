{...}: let
  namespace = "observability";

  # The host being scraped. cerberus is not a Kubernetes node: there is no
  # kubelet, no node-exporter DaemonSet pod and no Service for it, so the
  # kube-prometheus-stack has nothing in-cluster to discover it from.
  address = "192.168.1.105";
  port = 9100;
  host = "cerberus";

  # The job name is deliberately NOT "node-exporter".
  #
  # Every alert the kube-prometheus-stack itself ships for host metrics
  # (PrometheusRule-prometheus-node-exporter.yaml: NodeFilesystemAlmostOutOfSpace,
  # NodeFilesystemSpaceFillingUp, NodeSystemdServiceFailed, NodeClockSkewDetected,
  # ...) selects `job="node-exporter"`. Joining that job would mean cerberus is
  # alerted on twice, by two sets of thresholds that nobody chose together: its own
  # 85%/95% pair below, and the chart's 95%/97%-used pair, both critical at the top
  # end, so a full disk pages twice from two different runbooks. Those rules also
  # assume a `cluster` label and a kube_pod_info join that a machine outside the
  # cluster does not have.
  #
  # A separate job means: every alert that fires for cerberus is one of the rules in
  # ./cerberus-alerts.nix, with the thresholds and the routing written there. The
  # price is that the stock "Node Exporter / Nodes" Grafana dashboard (which
  # hardcodes job="node-exporter" in every query) will not offer cerberus; that is
  # reported rather than fixed, because cloning a dashboard is a separate change.
  jobName = "cerberus-node";
in {
  # Why a ScrapeConfig and not a selector-less Service + Endpoints + ServiceMonitor:
  #
  # * ScrapeConfig (monitoring.coreos.com/v1alpha1) exists precisely for scrape
  #   targets that are not Kubernetes objects: its `staticConfigs` says "this
  #   address", which is the truth here. It is one repo-owned object instead of
  #   three.
  # * A Service+Endpoints pair would be two objects that describe something that
  #   does not exist in the cluster: a Service with no selector and no pods, whose
  #   Endpoints are hand-maintained and go stale the moment cerberus's address
  #   changes, and which kube-controller-manager will happily adopt the moment
  #   anyone adds a selector. It is also not inert: a selector-less Service with
  #   Endpoints publishes `<name>.observability.svc.cluster.local` -> 192.168.1.105,
  #   i.e. it creates a cluster DNS alias for a LAN host that nothing in the app
  #   stack is meant to use.
  # * This repo already has a reason to distrust hand-rolled Endpoints: the chart's
  #   control-plane monitors were disabled because "these create Endpoint resources
  #   that ArgoCD excludes" (see prometheus-stack/default.nix).
  # * The ServiceMonitor route would not avoid the relabel either: a ServiceMonitor
  #   derives `instance` from the endpoint address, so the same
  #   `instance -> cerberus` relabel has to be written anyway.
  #
  # The one real cost of ScrapeConfig is that the CRD is still v1alpha1 (the operator
  # docs call it alpha). That is accepted: the installed operator is v0.94.2, the
  # CRD is installed by the prometheus-crds app in this same stack, and
  # `kubectl apply --server-side --dry-run=server` was run against it before any
  # push.
  #
  # Labels: `release = kube-prometheus-stack` is load-bearing. This Prometheus has
  # `spec.scrapeConfigSelector = matchLabels {release: kube-prometheus-stack}`
  # (scrapeConfigSelectorNilUsesHelmValues is on), so a ScrapeConfig without that
  # label is never read — the same reason the Garage ServiceMonitors and the
  # PrometheusRules carry it. `scrapeConfigNamespaceSelector` is `{}`, i.e. all
  # namespaces, so it lives with the rest of the monitoring objects.
  applications.prometheus-grafana.resources.scrapeConfigs.cerberus-node = {
    metadata = {
      inherit namespace;
      labels = {release = "kube-prometheus-stack";};
    };

    spec = {
      inherit jobName;

      # Same cadence as the Garage admin endpoints (30s), which is also the cadence
      # the node dashboards' rate windows assume. 10s timeout keeps a slow or sick
      # cerberus from tying up a scrape slot; the operator rejects a scrapeTimeout
      # >= scrapeInterval outright.
      scrapeInterval = "30s";
      scrapeTimeout = "10s";

      scheme = "http";
      metricsPath = "/metrics";

      staticConfigs = [
        {
          targets = ["${address}:${toString port}"];

          # A stable, human-readable label that survives every relabel below and
          # appears on every series and every alert. The address is the thing a
          # firewall or a `targets` page has to be checked against; `host` is the
          # thing an alert should say.
          labels = {inherit host;};
        }
      ];

      relabelings = [
        # Prometheus would otherwise put "192.168.1.105:9100" in `instance`, and
        # every alert would page with an IP. Replacing it (rather than adding a
        # second label and leaving the IP in place) is what keeps a disk-full page
        # readable on a phone, and keeps cerberus from ever appearing in a query
        # that has to be written as a regex over an address.
        #
        # Written the same way the Garage monitors stamp garage_cluster
        # (_modules/templates/garage-admin-metrics.nix): take __address__, replace
        # it with a constant, so nothing depends on which label the operator
        # happened to populate.
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
}
