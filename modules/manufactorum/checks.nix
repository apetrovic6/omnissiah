{self, ...}: {
  perSystem = {
    pkgs,
    lib,
    self',
    system,
    ...
  }: {
    # Every NixOS machine built for this system, so a new machine is
    # covered without being listed here. The Machines workflow
    # (.forgejo/workflows/machines.yml) builds `checks.x86_64-linux`.
    checks =
      lib.mapAttrs (_: machine: machine.config.system.build.toplevel)
      (lib.filterAttrs
        (_: machine: machine.pkgs.stdenv.hostPlatform.system == system)
        self.nixosConfigurations)
      // lib.optionalAttrs (system == "x86_64-linux" && self.nixosConfigurations ? ryza) {
        # Fails at eval if a Forgejo one-job slot unit names a mandatory
        # path the installer doesn't create first (HOM-30). The context is
        # discarded so the check never builds the test's enabled variant.
        forgejo-ephemeral-jobdir = pkgs.writeText "forgejo-ephemeral-jobdir.json" (
          builtins.unsafeDiscardStringContext (builtins.toJSON
            (import ../rites/_forgejo-ephemeral-jobdir-test.nix {inherit (self.nixosConfigurations) ryza;}))
        );
      };

    # One derivation that links every check, for building them all at once.
    packages.ci =
      pkgs.runCommand "ci-build" {
        # All check paths as a space-separated env var
        checkPaths = builtins.attrValues self'.checks;
      } ''
        mkdir -p "$out"
        # Just symlink everything into $out; works for files AND dirs
        for p in $checkPaths; do
          ln -s "$p" "$out"/
        done
      '';
  };
}
