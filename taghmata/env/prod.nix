{charts, ...}: {
  nixidy.target.repository = "https://github.com/apetrovic6/omnissiah.git";

  # Set the target branch the rendered manifests for _this_
  # environment should be pushed to in the repository defined
  # above.
  nixidy.target.branch = "master";

  # Set the target sub-directory to copy the generated
  # manifests to when running `nixidy switch .#dev`.
  nixidy.target.rootPath = "./taghmata/manifests/prod";

  applications.ingress-traefik = {
    yamls = [
    /* yaml */ ''

    ''
    ];
  };

  applications.metallb = {
    namespace = "metallb-system";
    createNamespace = true;

    helm.releases.metallb = {
      chart = charts.metallb.metallb;
    };

  yamls = [
     /* yaml */''
      apiVersion: metallb.io/v1beta1
      kind: IPAddressPool
      metadata:
        name: lan-pool
        namespace: metallb-system
        annotations:
          argocd.argoproj.io/sync-wave: "1"
      spec:
        addresses:
          - 192.168.1.240-192.168.1.250
      ''
      /* yaml */ ''
      apiVersion: metallb.io/v1beta1
      kind: L2Advertisement
      metadata:
        name: lan-adv
        namespace: metallb-system
        annotations:
          argocd.argoproj.io/sync-wave: "1"
      spec:
        ipAddressPools:
          - lan-pool
      ''
    ];    
  };
}
