{...}: {
  perSystem = {
    pkgs,
    inputs',
    ...
  }: {
    treefmt = {
      projectRootFile = "flake.nix";
      programs.alejandra.enable = true; # Nix formatter
      # add more: programs.prettier.enable = true; etc.
    };

    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        inputs'.clan-core.packages.clan-cli
        inputs'.nixidy.packages.default
        sops
        argocd
        nil
        nixd
        garage_2
      ];
    };
  };
}
