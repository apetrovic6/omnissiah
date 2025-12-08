{ ...}: {
  _class = "clan.service";
  manifest.name = "k8s-server";
  manifest.readme = "";

  roles.default.description = "Rke2 Server";

  roles.default.perInstance.nixosModule = {
    config,
    lib,
    pkgs,
    self,
    ...
  }: {
    imports = [
      self.nixosModules.noosphere
    ];

    services.imperium.taghmata.rke2.server = rec {
      enable = true;
      clusterName = "taghmata-omnissiah";
      serverAddr = "https://192.168.71.146:9345";
      cni = "calico";
      nodeLabels = [
        "role=control-plane"
        "cluster=${clusterName}"
      ];

      tokenFile = config.clan.core.vars.generators.taghmata-node-token.files.node-token.path;

      # nodeTaints = [ "node-role.kubernetes.io/control-plane=:NoSchedule" ];

      openFirewall = true;
    };
  };
}
