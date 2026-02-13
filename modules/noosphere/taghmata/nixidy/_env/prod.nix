{
  charts,
  config,
  ...
}: let
  domain = config.noosphere.domain;
in {
  imports = [
    ./apps/metrics-server
    ./apps/cloudnative-pg
    ./apps/longhorn
    ./apps/cloudnative-pg
    ./apps/metallb
    ./apps/sops-secrets-operator
    ./apps/alloy
    ./apps/cert-manager
    # ./apps/crowci
    ./apps/woodpecker-ci
    ./apps/prometheus-stack
    ./apps/yarr/seerr
    ./apps/csi-driver-nfs
    ./apps/garage
    ./apps/garage-ui
    ./apps/excalidraw
    ./apps/karakeep
    ./apps/bytestash
    ./apps/harbor
    ./apps/glances
    ./apps/reflector
    ./apps/keycloak-operator
    ./apps/forgejo
    ./apps/searxng
    ./apps/garage-operator
    ./apps/garage-main-ui
    ./apps/garage-backup-ui
    ./apps/local-path-provisioner
    ./apps/dagger
    ./apps/vikunja
    ./apps/pocket-id
    # ./apps/percona-mongodb
    # ./apps/unifi-network
  ];

  # CRD imports are now auto-discovered by the flake-module
  # nixidy.target is configured in flake.nix via noosphere.nixidy.envs.prod

  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = false;
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

  applications.coredns-config = {
    namespace = "kube-system";
    output.path = "./coredns";

    yamls = [
      ''
        apiVersion: helm.cattle.io/v1
        kind: HelmChartConfig
        metadata:
          name: rke2-coredns
          namespace: kube-system
        spec:
          valuesContent: |-
            servers:
            - zones:
              - zone: .
              port: 53
              plugins:
              - name: errors
              - name: health
                configBlock: |-
                  lameduck 10s
              - name: ready
              - name: kubernetes
                parameters: cluster.local cluster.local in-addr.arpa ip6.arpa
                configBlock: |-
                  pods insecure
                  fallthrough in-addr.arpa ip6.arpa
                  ttl 30
              - name: prometheus
                parameters: 0.0.0.0:9153
              - name: forward
                parameters: . /etc/resolv.conf
              - name: cache
                parameters: 30
              - name: loop
              - name: reload
              - name: loadbalance
            - zones:
              - zone: noosphere.uk
              port: 53
              plugins:
              - name: errors
              - name: cache
                parameters: 30
              - name: forward
                parameters: . 192.168.1.81
      ''
    ];
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
              annotations:
                metallb.io/allow-shared-ip: "noosphere"
                metallb.io/loadBalancerIPs: "192.168.1.240"

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
            cert-manager.io/cluster-issuer: letsencrypt-cloudflare
            glance/name: ArgoCD
            glance/icon:  di:argo-cd
            glance/url:  https://argocd.${domain}
            glance/description: "CD Tool"
            glance/id: argocd
            glance/parent: argocd
            category: gitops
        spec:
          ingressClassName: traefik
          tls:
            - secretName: argocd-tls
              hosts:
                - argocd.${domain}
          rules:
            - host: argocd.${domain}
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
    ];
  };
}
