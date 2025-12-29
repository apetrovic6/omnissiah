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
    imports = [
    ];

    systemd.services.iscsid.serviceConfig = {
      PrivateMounts = "yes";
      BindPaths = "/run/current-system/sw/bin:/bin";
    };

    environment.systemPackages = with pkgs; [nfs-utils openiscsi cryptsetup];
    boot.kernelModules = ["iscsi_tcp" "dm_crypt"];

    services.openiscsi = {
      enable = true;
      name = "iqn.2005-10.org.open-iscsi:${config.networking.hostName}";
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [80 443 9000];

    services.rke2 = {
      package = pkgs.rke2_1_34;
      autoDeployCharts = {
        argo-cd = {
          enable = true;
          name = "argo-cd";
          repo = "https://argoproj.github.io/argo-helm";
          version = "9.1.9";
          hash = "sha256-7HpAvR4N6mtkVSG9EDTGY4acVIBrhYkGUNicXBe83SQ=";
          createNamespace = true;
          targetNamespace = "argocd";

          values = {
            configs = {
              cm.oidc.config = ''
                name: Zitadel
                issuer: https://zitadel.noosphere.uk
                clientID: $zitadel-argocd-secret:oidc.zitadel.clientId
                clientSecret: $zitadel-argocd-secret:oidc.zitadel.clientSecret
                requestedScopes:
                  - openid
                  - profile
                  - email
                  - groups
                logoutURL: https://zitadel.noosphere.uk/oidc/v1/end_session
              '';
              rbac = {
                policy.default = "";
                scopes = "[groups]";
                policy.csv = ''
                  g, argocd_administrators, role:admin
                  g, argocd_users, role:readonly
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
