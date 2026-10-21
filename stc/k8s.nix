{...}: {
  _class = "clan.service";
  manifest.name = "k8s-server";
  manifest.readme = "";

  roles.default.description = "Rke2 dummy tag";

  roles.default.perInstance.nixosModule = {self, ...}: {};
}
