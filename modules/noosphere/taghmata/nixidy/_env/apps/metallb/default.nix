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
          # Starts at .251, not .250: an unidentified LAN device has
          # 192.168.1.250 set as a static IP and answers ARP for it with a
          # randomly-changing locally-administered (privacy) MAC whenever it
          # wakes. That intermittently blackholed every *.noosphere.uk service
          # for whichever clients cached the wrong MAC. Do not put .250 back in
          # the pool unless that device has actually been found and fixed.
          addresses = [
            "192.168.1.251-192.168.1.253"
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
