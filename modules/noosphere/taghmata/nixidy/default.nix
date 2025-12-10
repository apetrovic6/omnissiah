{withSystem, ...}: {
  flake.nixosModules.nixidy = withSystem "x86_64-linux" ({
    pkgs',
    inputs',
    ...
  }: {
    nixidyEnvs = inputs'.nixidy.lib.mkEnvs {
      inherit pkgs';

      envs = {
        dev.modules = [./env/dev.nix];
      };
    };
  });
}
