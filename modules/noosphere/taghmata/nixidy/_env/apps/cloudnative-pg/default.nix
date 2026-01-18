{
  charts,
  pkgs,
  ...
}: {
  applications.barman-cloud = {
    namespace = "cnpg-system";

    helm.releases.barman-cloud = {
      chart = charts.cloudnative-pg.plugin-barman-cloud;
    };
  };

  applications.cloudnativepg = let
    namespace = "cnpg-system";
  in {
    inherit namespace;
    createNamespace = true;

    helm.releases.cloudnative-pg = {
      chart = charts.cloudnative-pg.cloudnative-pg;

      values = {
        replicaCount = 3;

        # Enable Prometheus monitoring
        monitoring = {
          # Enable PodMonitor for Prometheus scraping
          podMonitorEnabled = true;
          podMonitorAdditionalLabels = {
            # This label is required for Prometheus to discover the operator's PodMonitor
            release = "kube-prometheus-stack";
          };

          # Enable Grafana dashboard ConfigMap
          grafanaDashboard = {
            create = true;
            configMapName = "cnpg-grafana-dashboard";
            labels = {
              # Label for Grafana sidecar to auto-discover the dashboard
              grafana_dashboard = "1";
            };
          };
        };

        # Configure operator to inherit labels from Clusters to their PodMonitors
        config = {
          data = {
            # Inherit the 'release' label from Clusters to their PodMonitors
            INHERITED_LABELS = "release";
            WATCH_NAMESPACE = "";
          };
        };
      };
    };
  };
}
