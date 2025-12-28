{charts, ...}: {
  imports = [
    ./apps/metrics-server
    ./apps/cloudnative-pg
    ./apps/longhorn
    ./apps/cloudnative-pg
    ./apps/metallb
    ./apps/sops-secrets-operator
    ./apps/alloy
    ./apps/cert-manager
    ./apps/zitadel
    ./apps/prometheus-stack
    ./apps/yarr/seerr
  ];

  nixidy.target.repository = "https://github.com/apetrovic6/omnissiah.git";
  # nixidy.chartsDir = ./charts;

  # Set the target branch the rendered manifests for _this_
  # environment should be pushed to in the repository defined
  # above.
  nixidy.target.branch = "master";

  # Set the target sub-directory to copy the generated
  # manifests to when running `nixidy switch .#dev`.
  nixidy.target.rootPath = "modules/noosphere/taghmata/nixidy/manifests/prod/";

  nixidy.applicationImports = [
    ../_generated/cert-manager-crd.nix
    ../_generated/metallb-crd.nix
    ../_generated/sops-secrets-operator-crd.nix
    ../_generated/cloudnativepg-crd.nix
    ../_generated/longhorn-crd.nix
    ../_generated/traefik-crd.nix
    ../_generated/alloy-operator-crd.nix
    ../_generated/kube-prometheus-stack-crd.nix
    ../_generated/prometheus-crd.nix
  ];

  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = true;
  };

  # applications.prometheus = {
  #   namespace = "observability";
  #   helm.releases.prometheus = {
  #     chart = charts.prometheus-community.prometheus;
  #     values = {};
  #   };
  # };

  # applications.seerr = {
  #   namespace = "yarr";
  #   createNamespace = true;

  #   helm.releases.seerr = {
  #     chart = lib.helm.downloadHelmChart {
  #       repo = "oci://ghcr.io/fallenbagel/jellyseerr";
  #       chart = "jellyseer-chart";
  #       version = "v2.7.3";
  #       chartHash = "";
  #     };

  #     # values = {};
  #   };
  # };

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
              kubernetesGateway:
                enabled: true
      ''

      ''
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: argocd-ip-root
          namespace: argocd
          annotations:
            traefik.ingress.kubernetes.io/router.entrypoints: websecure
        spec:
          ingressClassName: traefik
          tls:
            - secretName: argocd-tls
              hosts:
                - argocd.noosphere.uk
          rules:
            - host: argocd.noosphere.uk
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: argo-cd-argocd-server
                        port:
                          number: 80
      ''

      ''
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: longhorn-ip-root
          namespace: longhorn-system
          annotations:
            traefik.ingress.kubernetes.io/router.entrypoints: websecure
        spec:
          ingressClassName: traefik
          tls:
            - secretName: longhorn-tls
              hosts:
                - longhorn.noosphere.uk
          rules:
            - host: longhorn.noosphere.uk
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: longhorn-frontend
                        port:
                          number: 80
      ''
    ];
  };
}
