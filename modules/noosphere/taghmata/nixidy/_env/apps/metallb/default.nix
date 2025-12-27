{charts, ...}: {
  applications.metallb = let
    namespace = "metallb-system";
  in {
    output.path = "./metallb";
    inherit namespace;

    createNamespace = true;

    helm.releases.metallb = {
      chart = charts.metallb.metallb;
    };

    resources = {
      ipAddressPools.lan-pool = {
        metadata = {
          inherit namespace;
          annotations = {
            "argocd.argoproj.io/sync-wave" = "1";
          };
        };
        spec = {
          addresses = [
            "192.168.1.240-192.168.1.250"
          ];
        };
      };

      l2Advertisements.lan-adv = {
        metadata = {
          inherit namespace;
          annotations = {
            "argocd.argoproj.io/sync-wave" = "1";
          };
        };

        spec = {
          ipAddressPools = ["lan-pool"];
        };
      };
    };
  };
}
