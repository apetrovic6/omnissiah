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
        # path the installer doesn't create first (HOM-30), or class deadlines,
        # pool packaging and per-forge credentials regress. Discard context so the check
        # never builds the test's enabled variant.
        forgejo-ephemeral-jobdir = pkgs.writeText "forgejo-ephemeral-jobdir.json" (
          builtins.unsafeDiscardStringContext (builtins.toJSON
            (import ../rites/_forgejo-ephemeral-jobdir-test.nix {inherit (self.nixosConfigurations) ryza;}))
        );
        forgejo-ephemeral-ssh = let
          inherit (self.nixosConfigurations) cerberus;
          imported = cerberus.extendModules {
            modules = [self.nixosModules.forgejo-runner-ephemeral];
          };
          client = imported.extendModules {
            modules = [
              {
                services.imperium.forgejoEphemeral = {
                  enable = true;
                  pools.ugalabugala = {
                    forge = "ugalabugala";
                    scope.user = "manjo";
                    labels = ["nix-eph"];
                    dispatch = [4242];
                  };
                  inventory = lib.mapAttrs (_: entry: entry // {dispatcher = "cerberus";}) self.lib.ciSlots;
                };
                clan.core.vars.generators.forgejo-slotctl-ssh.files.id_ed25519.path = lib.mkForce "/run/secrets/fixture-key";
                clan.core.vars.generators.forgejo-ephemeral-ugalabugala.files.token.path = lib.mkForce "/run/secrets/fixture-pat";
              }
            ];
          };
          ssh = lib.getExe' client.pkgs.openssh "ssh";
          wrapper = client.config.services.imperium.forgejoEphemeral.internal.sshClients.ryza;
          dispatcher = client.config.systemd.services."forgejo-ephemeral-dispatcher@ryza-eph-1";
          # Change only the executable in a throwaway copy of the deployed
          # wrapper. -G runs OpenSSH's real parser without connecting.
          offlineSsh = pkgs.writeShellScript "slotctl-ssh-offline" ''
            set -eu
            ${ssh} -G "$@"
            if [[ $# != 10 || $8 != slot-host || $9 != -- || ''${10} != "$SLOTCTL_TEST_COMMAND" ]]; then
              printf 'unexpected wrapper argument: %q\n' "$@" >&2
              exit 1
            fi
          '';
        in
          assert !imported.config.services.imperium.forgejoEphemeral.enable;
          assert !imported.config.microvm.host.enable;
          assert imported.config.system.build.toplevel.drvPath == cerberus.config.system.build.toplevel.drvPath;
          assert !client.config.microvm.host.enable;
          assert lib.hasInfix (builtins.unsafeDiscardStringContext "--ssh-command ${wrapper} ")
          (builtins.unsafeDiscardStringContext dispatcher.serviceConfig.ExecStart);
          assert lib.hasSuffix " --vm-deadline 11520" dispatcher.serviceConfig.ExecStart;
            pkgs.runCommand "forgejo-ephemeral-ssh" {} ''
              export CREDENTIALS_DIRECTORY="$TMPDIR/credentials"
              export RUNTIME_DIRECTORY="$TMPDIR/runtime"
              export SLOTCTL_TEST_COMMAND='--slot ryza-eph-1 check-space'
              mkdir -p "$CREDENTIALS_DIRECTORY" "$RUNTIME_DIRECTORY"
              touch "$CREDENTIALS_DIRECTORY/slotctl-ssh-key"
              substitute ${wrapper} ./slotctl-ssh --replace-fail ${ssh} ${offlineSsh}
              chmod +x ./slotctl-ssh
              ./slotctl-ssh "$SLOTCTL_TEST_COMMAND" > "$out"
              grep -Fx 'hostname ${self.lib.hosts.ryza}' "$out"
              grep -Fx 'bindaddress ${self.lib.hosts.cerberus}' "$out"
              grep -Fx 'user root' "$out"
              grep -Fx 'batchmode yes' "$out"
            '';
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
