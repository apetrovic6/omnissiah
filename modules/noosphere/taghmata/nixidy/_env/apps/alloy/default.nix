{charts, }: {
  applications.alloy = {
    namespace = "alloy";
    createNamespace = true;
    helm.releases.alloy = {
        chart = charts.alloy;     
        values = {
          autoscaling.enabled = true;
        };
    };
  };
}
