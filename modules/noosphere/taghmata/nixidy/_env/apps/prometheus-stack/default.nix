{charts, ...}: {
  applications.prometheus = {
    namespace = "observability";
    createNamespace = true;

    helm.releases.kube-prometheus-stack = {
      chart = charts.prometheus-community.kube-prometheus-stack;
      includeCRDs= true;

      values = {

        # ingress = {
        #   enabled = true;
        #   ingressClassName = "traefik";
        #   hosts =
        # };
      };
    };
  };
}
