{...}: {
  perSystem = {
    pkgs,
    inputs',
    self',
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
        self'.packages.tofunix
        # Structural search and rewrite by syntax tree, Nix included
        # (`ast-grep run -l nix -p 'lib.mkIf $C $B'`); see the ast-grep skill.
        ast-grep
      ];
    };
  };
}
