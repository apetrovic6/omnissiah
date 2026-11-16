{self, ...}: {
  imports = [self.nixosModules.taghmata-node];

  services.imperium.forgejoRunner.resources.memory = 3;
}
