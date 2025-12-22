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
      manifests.rke2-traefik-config = {
        enable = true;
        target = "rke2-traefik-config.yaml";
        content = {
          apiVersion = "helm.cattle.io/v1";
          kind = "HelmChartConfig";
          metadata = {
            name = "rke2-traefik";
            namespace = "kube-system";
          };

          spec = {
            valuesContent = {
              hub.apimanagement.admission.listenAddr = "0.0.0.0";
              providers.kubernetesGateway.enabled = true;
            };
          };
        };
      };

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
