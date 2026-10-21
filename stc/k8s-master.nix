{...}: {
  _class = "clan.service";
  manifest.name = "k8s-master";

  manifest.readme = "Configuration for a master node";

  roles.default.description = "Rke2 master nodeconfig";

  roles.default.perInstance.nixosModule = {
    config,
    pkgs,
    self,
    ...
  }: {
    imports = [
      self.nixosModules.noosphere
    ];

    nixpkgs.overlays = [self.overlays.rke2];

    # base turns on NetworkManager and clan-core turns on systemd-networkd, so
    # without this both run DHCP on the NIC and lease two different addresses.
    # The etcd peer cert gets the primary one while outbound traffic leaves
    # from the other, and the existing members reject the join with
    # `tls: "<ip>" does not match`. networkd alone owns the wired link.
    #
    # Not networking.networkmanager.unmanaged: that lands in the main
    # NetworkManager.conf, and the rke2 module's conf.d/rke2-canal.conf sets
    # unmanaged-devices again, which replaces rather than merges. This file
    # sorts after it and appends with `+=`, keeping the CNI exclusions.
    environment.etc."NetworkManager/conf.d/rke2-wired.conf".text = ''
      [keyfile]
      unmanaged-devices+=type:ethernet
    '';

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
    };

    services.imperium.taghmata.rke2.registryCache = {
      enable = true;
      dockerProject = "docker_cache";

      # ghcr.io is deliberately NOT mirrored, to keep CNPG off Harbor.
      #
      # Harbor's own database is a CNPG cluster, so routing
      # ghcr.io/cloudnative-pg/* through Harbor makes Harbor a prerequisite for
      # starting the thing Harbor depends on. On 2026-10-02 that closed into a
      # deadlock: a node lost the Longhorn CSI driver, the Harbor DB primary
      # living on it could not restart, Harbor served nothing, and the node had
      # no working mirror to pull its way out. It took ~17 minutes to break out
      # on its own, via containerd's last-resort fallback to the upstream.
      #
      # This cannot be expressed as an exclusion: RKE2 mirror keys are
      # hostnames only, so the choice is per registry, not per repository.
      # ghcr.io costs little to give up -- 12 distinct images cluster-wide
      # against 63 on docker.io -- and four of those twelve are the CNPG ones
      # this is about.
      #
      # Still unbroken, and not fixable the same way: docker.io/goharbor/* and
      # docker.io/longhornio/* are the other two links, and dropping the
      # docker.io mirror wholesale is too high a price. Those need the images
      # preloaded on every node instead.
      ghcrProject = null;
    };

    services.rke2 = {
      package = pkgs.rke2_1_35;
      autoDeployCharts = {
        argo-cd = {
          enable = true;
          name = "argo-cd";
          repo = "https://argoproj.github.io/argo-helm";
          version = "10.9.6";
          hash = "sha256-btqQvdGN5ThRHJuayhynunocpbkZ9ZhxTQ6RzXFV0Rk=";
          createNamespace = true;
          targetNamespace = "argocd";

          values = {
            configs = {
              cm = {
                url = "https://argocd.${config.noosphere.domain}";
                "oidc.config" = ''
                  name: PocketID
                  issuer: https://${config.noosphere.sso.url}
                  clientID: $argo-oidc:client-id
                  clientSecret: $argo-oidc:client-secret
                  enablePKCEAuthentication: false
                  requestedScopes:
                    - openid
                    - profile
                    - email
                    - groups
                  logoutURL: https://${config.noosphere.sso.url}/api/oidc/end-session
                '';
              };

              params = {
                "server.insecure" = true;
              };

              rbac = {
                "policy.default" = "";
                scopes = "[groups]";
                "policy.csv" = ''
                  g, ArgoCDAdmins, role:admin
                  g, ArgoCDUsers, role:readonly
                '';
              };
            };
          };
        };
      };
    };

    services.imperium.taghmata.rke2.server = rec {
      enable = true;
      clusterName = "taghmata-omnissiah";
      cni = "calico";
      multus = true;
      nodeLabels = [
        "role=control-plane"
        "cluster=${clusterName}"
      ];

      extraFlags = [
        "--ingress-controller=traefik"
      ];

      tokenFile = config.clan.core.vars.generators.taghmata-node-token.files.node-token.path;

      nodeTaints = ["node-role.kubernetes.io/control-plane=:NoSchedule"];

      openFirewall = true;

      serverAddr = "https://192.168.1.138:9345";
    };
  };
}
