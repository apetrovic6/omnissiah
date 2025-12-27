{lib, ...}: {
  applications.alloy = {
    namespace = "alloy";
    createNamespace = true;
    helm.releases.alloy = {
      chart = lib.helm.downloadHelmChart {

  repo = "https://grafana.github.io/helm-charts";
  chart = "alloy-operator";
  version = "1.5.1";
  chartHash = "";

      };
      values = {
      };
    };
  };
}
