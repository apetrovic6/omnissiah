{charts, ...}: {
  nixidy.target.repository = "https://github.com/apetrovic6/omnissiah.git";

  # Set the target branch the rendered manifests for _this_
  # environment should be pushed to in the repository defined
  # above.
  nixidy.target.branch = "master";

  # Set the target sub-directory to copy the generated
  # manifests to when running `nixidy switch .#dev`.
  nixidy.target.rootPath = "./taghmata/manifests/prod";

  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = true;
  };

  # applications.tailscale-operator = {};

  applications.cert-manager = {
    output.path = "./cert-manager";
    namespace = "cert-manager";
    createNamespace = true;

    helm.releases.cert-manager = {
      chart = charts.jetstack.cert-manager;
      values = {
        global.leaderElection.namespace = "cert-manager";
        crds.enabled = true;
      };
    };
  };

  applications.sops-secrets = {
    output.path = "./sops-secrets-operator";
    namespace = "sops";
    createNamespace = true;

    helm.releases.sops-secrets-operator = {
      chart = charts.isindir.sops-secrets-operator;
    };
  };

  applications.ingress-traefik-load-balancer-config = {
    namespace = "kube-system";
    output.path = "./traefik";

    yamls = [
      ''
        apiVersion: helm.cattle.io/v1
        kind: HelmChartConfig
        metadata:
          name: rke2-traefik
          namespace: kube-system
        spec:
          valuesContent: |-
            service:
              type: LoadBalancer

            providers:
              kubernetesIngress: false
              kubernetesGateway:
                enabled: true
              gateway:
                namespacePolicy: All
      ''

      ''
        apiVersion: gateway.networking.k8s.io/v1
        kind: GatewayClass
        metadata:
          name: traefik
        spec:
          controllerName: traefik.io/gateway-controller

      ''

      ''
        apiVersion: gateway.networking.k8s.io/v1
        kind: Gateway
        metadata:
          name: edge
          namespace: kube-system
        spec:
          gatewayClassName: traefik
          listeners:
            - name: web
              protocol: HTTP
              port: 80   # OR 8000 depending on your Traefik entrypoints
              allowedRoutes:
                namespaces:
                  from: All

      ''

      ''
        apiVersion: gateway.networking.k8s.io/v1
        kind: HTTPRoute
        metadata:
          name: argocd-ip
          namespace: argocd
        spec:
          parentRefs:
            - name: edge
              namespace: kube-system
              sectionName: web
          rules:
            - matches:
                - path:
                    type: PathPrefix
                    value: /
              backendRefs:
                - name: argo-cd-argocd-server
                  port: 80
      ''
    ];
  };

  applications.metallb = {
    output.path = "./metallb";
    namespace = "metallb-system";
    createNamespace = true;

    helm.releases.metallb = {
      chart = charts.metallb.metallb;
    };

    yamls = [
      /*
      yaml
      */
      ''
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
      /*
      yaml
      */
      ''
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
