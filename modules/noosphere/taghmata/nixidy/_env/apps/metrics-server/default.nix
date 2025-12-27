{charts, ...}:
{
  applications.metrics-server = {

    helm.releases.metrics-server = {
      namespace = "kube-system";
      chart = charts.kubernetes-sigs.metrics-server;
    };
  };
}
