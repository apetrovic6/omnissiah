{lib, ...}: {
  applications.alloy = {
    namespace = "alloy";
    createNamespace = true;
    helm.releases.alloy = {
      chart = lib.helm.downloadHelmChart {
        repo = "https://grafana.github.io/helm-charts";
        chart = "alloy-operator";
        version = "0.3.15";
        chartHash = "sha256-hallQsrgu6gnKE5jxkPEPWUh28R2E0VykcuTw0kXfq0=";
      };
      values = {
        replicaCount = 3;
      };
    };
  };
}
