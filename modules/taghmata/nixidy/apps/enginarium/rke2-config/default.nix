# Configuration of the charts RKE2 itself installs (Calico, CoreDNS, Multus,
# Traefik), as HelmChartConfig objects that RKE2's helm controller merges into
# its own releases.
{...}: {
  nixidy.envs.prod.apps.rke2-config = {
    config,
    cartographa,
    ...
  }: let
    domain = config.noosphere.domain;
  in {
    applications.calico-config = {
      namespace = "kube-system";
      output.path = "./calico";

      yamls = [
        ''
          apiVersion: helm.cattle.io/v1
          kind: HelmChartConfig
          metadata:
            name: rke2-calico
            namespace: kube-system
          spec:
            valuesContent: |-
              installation:
                calicoNetwork:
                  # Pin the pod MTU rather than letting Felix auto-detect it.
                  # Calico's default mtuIfacePattern does not match servitor's
                  # "end0" (the Amlogic meson driver's name), so detection failed
                  # there and fell back to 1410 while every other node computed
                  # 1450. Mixed MTUs across the VXLAN overlay are a PMTU black
                  # hole: small packets pass, full-size ones are dropped, and TCP
                  # only finds out by timing out.
                  mtu: 1450
        ''
      ];
    };

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
                # - name: hosts
                #   configBlock: |-
                #     192.168.1.240 forge.noosphere.uk
                #     fallthrough
                - name: cache
                  parameters: 30
                - name: forward
                  parameters: . ${cartographa.hosts.cerberus}
              # Split-horizon for the Caddy LAB_DOMAIN zone, the same way noosphere.uk
              # is pinned above, for one concrete reason: Alertmanager publishes to
              # https://ntfy.ugalabugala.org (machines/cerberus/ntfy.nix), and that name
              # must answer 192.168.1.105 from inside a pod. Measured on 2026-11-06:
              #   dig @192.168.1.105 ntfy.ugalabugala.org -> 192.168.1.105   (Technitium,
              #     zone is wildcarded, and CoreDNS' `forward . /etc/resolv.conf` lands
              #     on the same server because rke2 gives the coredns pod the node's
              #     resolver: its /etc/resolv.conf is `nameserver 192.168.1.105`)
              #   dig @1.1.1.1 ha.ugalabugala.org          -> 152.53.34.16   (the VPS)
              # So it works today only because every node's resolver is Technitium, and
              # this lab has already lost that once: cerberus ran NetworkManager and
              # networkd on one NIC at the same time and "both pushed the router's DNS
              # onto the link", while machines/cerberus/configuration.nix documents that
              # the router and 9.9.9.9 answer these names with the VPS. A node handed
              # DHCP DNS again would silently start sending a pod's ugalabugala.org
              # lookups to the public answer, and the alert webhook would go to the VPS
              # instead of to ntfy. Pinned, the zone does not depend on that.
              - zones:
                - zone: ugalabugala.org
                port: 53
                plugins:
                - name: errors
                - name: cache
                  parameters: 30
                - name: forward
                  parameters: . ${cartographa.hosts.cerberus}
        ''
      ];
    };

    applications.multus-config = {
      namespace = "kube-system";
      output.path = "./multus";

      yamls = [
        ''
          apiVersion: helm.cattle.io/v1
          kind: HelmChartConfig
          metadata:
            name: rke2-multus
            namespace: kube-system
          spec:
            valuesContent: |-
              rke2-whereabouts:
                enabled: true
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
                # Traefik chart v40 (rke2-traefik 40.1.010+) renders the Service
                # spec straight from `service.spec`; a top-level `service.type` is
                # silently ignored, so the Service falls back to ClusterIP and the
                # MetalLB VIP -- and all external ingress -- disappears.
                spec:
                  type: LoadBalancer
                annotations:
                  metallb.io/allow-shared-ip: "noosphere"
                  metallb.io/loadBalancerIPs: "${cartographa.vips.traefik}"

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
  };
}
