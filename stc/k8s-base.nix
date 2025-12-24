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
