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
      ghcrProject = "github_cache";
    };

    # Make mount helpers visible in FHS-ish locations Longhorn expects via nsenter
    systemd.tmpfiles.rules = [
      "d /mnt/storage/garage 0755 root root -"
      "L+ /bin/mount - - - - ${pkgs.util-linux}/bin/mount"
      "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"

      # NFS helper name can vary by distro; these two paths cover common expectations
      "L+ /sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"
      "L+ /usr/sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"

      # iSCSI tools for Longhorn volume attachment
      "L+ /sbin/iscsiadm - - - - ${pkgs.openiscsi}/bin/iscsiadm"
      "L+ /usr/bin/iscsiadm - - - - ${pkgs.openiscsi}/bin/iscsiadm"
    ];

    environment.systemPackages = with pkgs; [nfs-utils util-linux openiscsi cryptsetup];
    boot.kernelModules = ["iscsi_tcp" "dm_crypt"];

    services.openiscsi = {
      enable = true;
      name = "iqn.2005-10.org.open-iscsi:${config.networking.hostName}";
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [80 443 9000];

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
          version = "9.3.4";
          hash = "sha256-dpTJFsJgs8rZU3ejxgyggLSpeYGGZnFTPLeQVMV0wG0=";
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
