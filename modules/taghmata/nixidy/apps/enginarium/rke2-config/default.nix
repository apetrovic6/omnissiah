# Configuration of the charts RKE2 itself installs (Calico, CoreDNS, Multus,
# Traefik), as HelmChartConfig objects that RKE2's helm controller merges into
# its own releases.
{self, ...}: {
  nixidy.envs.prod.apps.rke2-config = {
    config,
    cartographa,
    ...
  }: let
    domain = config.noosphere.domain;

    # The LAN's Blocky resolvers; CoreDNS' forward picks among them and skips
    # one that stops answering (its health checks), so a Blocky restart
    # never breaks lookups from pods.
    lanResolvers = builtins.concatStringsSep " " cartographa.lan.resolvers;

    # `<machine>.omnissiah.internal` for every address in cartographa, answered
    # by CoreDNS itself (below). ExternalName Services point Traefik at these
    # (_modules/ingress.nix `outside`), so routing to a machine outside the
    # cluster never depends on the LAN resolvers. The joiner carries the indentation
    # the lines need inside the YAML block below; interpolated text is not
    # re-indented by Nix.
    machineHosts =
      builtins.concatStringsSep "\n          " (map (name: "${cartographa.hosts.${name}} ${name}.omnissiah.internal")
        (builtins.attrNames cartographa.hosts));
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
                  parameters: . ${lanResolvers}
              # Split-horizon for the Caddy LAB_DOMAIN zone, the same way noosphere.uk
              # is pinned above, for one concrete reason: Alertmanager publishes to
              # https://ntfy.ugalabugala.org (machines/cerberus/ntfy.nix), and that name
              # must answer 192.168.1.105 from inside a pod. Measured on 2026-11-06:
              #   dig @192.168.1.105 ntfy.ugalabugala.org -> 192.168.1.105   (then
              #     Technitium, now Blocky; CoreDNS' `forward . /etc/resolv.conf` lands
              #     on the same servers because rke2 gives the coredns pod the node's
              #     resolvers)
              #   dig @1.1.1.1 ha.ugalabugala.org          -> 152.53.34.16   (the VPS)
              # So it would work only because every node's resolver is a LAN Blocky, and
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
                  parameters: . ${lanResolvers}
              # The clan's machines by name, from cartographa, answered here and
              # nowhere else: the targets of ExternalName Services. `.internal`
              # is the TLD reserved for private use, so it can never shadow a
              # public name. No fallthrough: an unknown machine is NXDOMAIN.
              - zones:
                - zone: omnissiah.internal
                port: 53
                plugins:
                - name: errors
                - name: hosts
                  configBlock: |-
                    ${machineHosts}
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
                # Lets an Ingress route to a machine outside the cluster through
                # an ExternalName Service (_modules/ingress.nix `outside`). Off by
                # default because whoever can create Services can then point
                # Traefik at any host it reaches; here only ArgoCD does.
                kubernetesIngress:
                  allowExternalNameServices: true
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

  perSystem = {system, ...}: {
    # Traefik is installed by RKE2; only its CRD options are needed here.
    nixidy.crds.definitions.traefik.chart = self.inputs.nixhelm.chartsDerivations.${system}.traefik.traefik;
  };
}
