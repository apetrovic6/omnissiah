{
  charts,
  pkgs,
  ...
}: let
  barmanVersion = "0.10.0";
  barmanManifest = pkgs.fetchurl {
    url = "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${barmanVersion}/manifest.yaml";
    hash = "sha256-9yjeqQqt490v60xLOTX6dLyHQwdjU8lwY1kbHQrUuKQ=";
  };
in {
  # TODO: Replace with the helm chart
  # https://artifacthub.io/packages/helm/cloudnative-pg/plugin-barman-cloud
  applications.barman-cloud = {
    namespace = "cnpg-system";
    yamls = [
      (builtins.readFile barmanManifest)
    ];
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
            prometheus = "kube-prometheus";
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
      };
    };
  };
}
