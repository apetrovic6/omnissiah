{...}: {
  _class = "clan.service";
  manifest.name = "k8s-server";
  manifest.readme = "";

  roles.default.description = "Rke2 Server";

  roles.default.perInstance.nixosModule = {self, ...}: {
    imports = [
      self.nixosModules.noosphere
    ];

    services.imperium.taghmata.rke2.server = {
      enable = true;
      serverAddr = "https://192.168.1.48:9345";
    };
  };
}
