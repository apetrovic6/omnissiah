{lib, ...}: let
  inherit (lib) mkOption types;
in {
  # Scrapes a GarageCluster's admin API (/metrics on the admin port) with a
  # ServiceMonitor the kube-prometheus-stack Prometheus will actually pick up.
  #
  # Why it is written this way:
  #
  # * The Prometheus in `observability` selects monitors with
  #   `spec.serviceMonitorSelector = matchLabels {release: kube-prometheus-stack}`
  #   (`serviceMonitorSelectorNilUsesHelmValues` is on), so a monitor without
  #   that label is simply never read. That is also how CNPG's PodMonitors get
  #   scraped: `pg-ncps-rev1` carries the same label.
  #
  # * The monitor has to live in the namespace of the Service it selects
  #   (garage-operator), so it belongs with the Garage app, not with Prometheus.
  #
  # * The operator already creates a Service per cluster (`garage-main`,
  #   `garage-backup`) that exposes 3900/3902/3903, but it shares one label set
  #   with the matching `*-headless` Service (which only publishes the RPC port
  #   3901). Selecting through operator-owned objects means betting on a label
  #   coincidence plus port-name filtering; so we scrape the repo-owned
  #   `*-admin` Services instead and label those with a pair nothing else in
  #   the namespace has.
  #
  # * /metrics needs no credential here: Garage v2.3.0 serves it on the admin
  #   port without auth (verified with a direct scrape), and neither cluster's
  #   rendered garage.toml sets `metrics_token`. An `authorization` block with a
  #   Secret would be the fallback if that ever changes; the existing
  #   `garage-main-admin-token` / `garage-backup-admin-token` Secrets are the
  #   keys to reference then. Do not hand-create a monitoring token.
  templates.garageAdminMetrics = {
    options = {
      namespace = mkOption {
        type = types.str;
        description = "Namespace holding the Garage admin Service and this ServiceMonitor.";
      };

      cluster = mkOption {
        type = types.str;
        description = "GarageCluster name; copied onto every series as the garage_cluster label.";
      };

      adminService = mkOption {
        type = types.str;
        description = "Name of the Service that exposes the Garage admin API port.";
      };

      adminPort = mkOption {
        type = types.str;
        default = "admin";
        description = "Name of the Service port to scrape (`.spec.ports[].name`).";
      };

      scrapeInterval = mkOption {
        type = types.str;
        default = "30s";
        description = "Scrape interval for the admin metrics endpoint.";
      };

      scrapeTimeout = mkOption {
        type = types.str;
        default = "15s";
        description = "Must stay below scrapeInterval or the operator rejects the monitor.";
      };
    };

    output = {
      name,
      config,
      ...
    }: {
      # A template's output is spliced under `applications.<app>.resources`, so
      # the keys below are resource kinds, not full option paths (same shape as
      # _modules/templates/garage-object-store.nix emitting `objectStores.${name}`).
      #
      # These Services have no labels of their own today, and a ServiceMonitor
      # selects Services by label. Adding the pair makes the selection
      # unambiguous and puts the contract in one place: the Service declares it
      # is scrapeable, the monitor asks for exactly that.
      services.${config.adminService}.metadata.labels = {
        "garage-monitoring/cluster" = config.cluster;
        "garage-monitoring/role" = "admin-metrics";
      };

      serviceMonitors.${name} = {
        metadata = {
          namespace = config.namespace;
          labels = {release = "kube-prometheus-stack";};
        };

        spec = {
          selector.matchLabels = {
            "garage-monitoring/cluster" = config.cluster;
            "garage-monitoring/role" = "admin-metrics";
          };

          namespaceSelector.matchNames = [config.namespace];

          endpoints = [
            {
              port = config.adminPort;
              path = "/metrics";
              scheme = "http";
              interval = config.scrapeInterval;
              scrapeTimeout = config.scrapeTimeout;

              relabelings = [
                # Constant, not derived from Service metadata: one monitor covers
                # exactly one cluster, and every alert expression groups on
                # garage_cluster. A label name we own also survives an operator
                # that renames its own Services.
                {
                  action = "replace";
                  sourceLabels = ["__address__"];
                  regex = ".*";
                  replacement = config.cluster;
                  targetLabel = "garage_cluster";
                }
                # Alerts about a storage node are actionable per machine: every
                # Garage storage pod sits on its own host (pod anti-affinity).
                {
                  action = "replace";
                  sourceLabels = ["__meta_kubernetes_pod_node_name"];
                  targetLabel = "node";
                }
              ];
            }
          ];
        };
      };
    };
  };
}
