# Shared runner setup and registration flow: modules/rites/forgejo-runner.nix.
{
  self,
  pkgs,
  ...
}: {
  imports = [self.nixosModules.forgejo-runner];

  services.imperium.forgejoRunner = {
    enable = true;
    extraHostPackages = [
      # Drives the Dagger pipeline in the `fishing` repo. Must match the
      # engine container version in ./dagger.nix (v0.21.8) — the SDK
      # refuses to start a session against a different engine.
      self.inputs.dagger-cli.packages.${pkgs.stdenv.hostPlatform.system}.dagger
    ];
  };
}
