{charts, ...}: {
  applications.metallb = let
    namespace = "metallb-system";
  in {
    output.path = "./metallb";
    inherit namespace;

    createNamespace = true;

    helm.releases.metallb = {
      chart = charts.metallb.metallb;
      values = {
        controller.replicas = 3;
      };
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
            "192.168.1.250-192.168.1.253"
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
          interfaces = ["enp1s0"];
          # nodeSelectors = [
          #   {
          #     matchLabels = {
          #       "kubernetes.io/hostname" = "sol";
          #     };
          #   }
          # ];
        };
      };
    };
  };
}
