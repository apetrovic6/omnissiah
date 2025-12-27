{charts, ...}: {
  applications.metrics-server = {
    namespace = "metrics-server";
    createNamespace = true;
    helm.releases.metrics-server = {
      chart = charts.kubernetes-sigs.metrics-server;
    };
  };
}
