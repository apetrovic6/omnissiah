{...}: {
  _class = "clan.service";
  manifest.name = "k8s-base";
  manifest.readme = "";

  roles.default.description = "Rke2 Base config";

  roles.default.perInstance.nixosModule = {
    config,
    lib,
    pkgs,
    self,
    ...
  }: {
    imports = [];

    nixpkgs.overlays = [self.overlays.rke2];

    services.tailscale = {
      enable = lib.mkForce false;
    };

    swapDevices = [
      {
        size = 50 * 1024;
        device = "/mnt/storage/swapFile";
      }
    ];

    systemd.services.iscsid.serviceConfig = {
      PrivateMounts = "yes";
      BindPaths = "/run/current-system/sw/bin:/bin";
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

    # Make mount helpers visible in FHS-ish locations Longhorn expects via nsenter
    systemd.tmpfiles.rules = [
      "d /mnt/storage/garage 0755 root root -"
      "d /var/lib/nfs 0755 root root -"
      "d /var/lib/nfs/sm 0755 root root -"
      "d /var/lib/nfs/sm.bak 0755 root root -"
      "L+ /bin/mount - - - - ${pkgs.util-linux}/bin/mount"
      "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"

      # NFS helper name can vary by distro; these two paths cover common expectations
      "L+ /sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"
      "L+ /usr/sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"

      # iSCSI tools for Longhorn volume attachment
      "L+ /sbin/iscsiadm - - - - ${pkgs.openiscsi}/bin/iscsiadm"
      "L+ /usr/bin/iscsiadm - - - - ${pkgs.openiscsi}/bin/iscsiadm"

      # fstrim for Longhorn trimFilesystem action (nsenter uses this path)
      "L+ /usr/bin/fstrim - - - - ${pkgs.util-linux}/bin/fstrim"
    ];

    environment.systemPackages = with pkgs; [nfs-utils util-linux openiscsi cryptsetup];
    boot.kernelModules = ["iscsi_tcp" "dm_crypt"];

    services.rpcbind.enable = true;
    systemd.packages = [pkgs.nfs-utils];
    systemd.services.rpc-statd.wantedBy = ["multi-user.target"];

    services.openiscsi = {
      enable = true;
      name = "iqn.2005-10.org.open-iscsi:${config.networking.hostName}";
    };

    networking.interfaces.enp2s0.useDHCP = false;

    # Prevent NetworkManager from managing k8s node interfaces
    environment.etc."NetworkManager/conf.d/storage-network.conf".text = ''
      [keyfile]
      unmanaged-devices=interface-name:enp2s0;interface-name:enp1s0
    '';

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
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

      # nodeTaints = [ "node-role.kubernetes.io/control-plane=:NoSchedule" ];

      openFirewall = true;
    };
  };
}
