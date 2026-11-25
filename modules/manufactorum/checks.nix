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
        # Fails at eval if a Hermes delegation guard rail stops firing: a work
        # subagent able to reach a personal provider, a meta provider id, a
        # tier outside its allowlist (README "Hermes delegation tiers").
        hermes-delegation-tiers = pkgs.writeText "hermes-delegation-tiers.json" (
          builtins.unsafeDiscardStringContext (builtins.toJSON
            (import ../rites/_hermes-delegation-tiers-test.nix {inherit (self.nixosConfigurations) ryza;}))
        );
        # The nix-eph dispatcher and slotctl tests (HOM-30..32): a loopback
        # Forgejo, a fake systemctl, slotctl in-process and as a real child.
        # Run with the python3 the slots' host deploys, not a newer one.
        forgejo-ephemeral-dispatcher-tests =
          pkgs.runCommand "forgejo-ephemeral-dispatcher-tests" {
            nativeBuildInputs = [self.nixosConfigurations.ryza.pkgs.python3];
          } ''
            cp ${../rites/_forgejo-ephemeral-dispatcher.py} _forgejo-ephemeral-dispatcher.py
            cp ${../rites/_forgejo-slotctl.py} _forgejo-slotctl.py
            cp ${../rites/_forgejo-ephemeral-dispatcher-test.py} test.py
            python3 -B test.py
            touch "$out"
          '';
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
