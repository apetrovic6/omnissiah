# Shared runner setup and registration flow: modules/rites/forgejo-runner.nix.
# sccache: host-step cargo builds cache into the `sccache` bucket on garage-main
# (modules/rites/sccache.nix).
{self, ...}: {
  imports = [
    self.nixosModules.forgejo-runner
    self.nixosModules.sccache
  ];

  services.imperium.forgejoRunner.enable = true;
  services.imperium.sccache.enable = true;
}
