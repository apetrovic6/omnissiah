{...}: {
  _class = "clan.service";
  manifest.name = "k8s-server";
  manifest.readme = "";

  roles.default.description = "Rke2 Server";

  roles.default.perInstance.nixosModule = {self, ...}: {
    imports = [
      self.nixosModules.noosphere
      self.nixosModules.taghmata
      self.nixosModules.reliquary
    ];

    services.imperium.taghmata.rke2.server = {
      enable = true;
      serverAddr = "https://${self.lib.hosts.terra}:9345";
    };
  };
}
