# Shared runner setup and registration flow: modules/rites/forgejo-runner.nix.
{self, ...}: {
  imports = [self.nixosModules.forgejo-runner];

  services.imperium.forgejoRunner.enable = true;
}
