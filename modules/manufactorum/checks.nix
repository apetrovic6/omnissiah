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
          inherit (self.nixosConfigurations) ryza cerberus;
          inherit (self.lib) ciDispatcher;
          local = ryza.extendModules {
            specialArgs.ciDispatcher =
              ciDispatcher
              // {
                remote = false;
                trustedJobs = false;
              };
          };
          fixture = fleet: let
            inherit (fleet) host trustedJobs;
            specialArgs.ciDispatcher = fleet;
            client = self.nixosConfigurations.${host}.extendModules {
              inherit specialArgs;
              # Unenrolled Clan vars otherwise report /no-such-path. Use the
              # deployed SOPS path shape without creating any secret files.
              modules = [
                {
                  clan.core.vars.generators = {
                    forgejo-ephemeral-ugalabugala.files.token.path = lib.mkForce "/run/secrets/vars/forgejo-ephemeral-ugalabugala/token";
                    forgejo-ephemeral-noosphere.files.token.path = lib.mkForce "/run/secrets/vars/forgejo-ephemeral-noosphere/token";
                    forgejo-slotctl-ssh.files.id_ed25519.path = lib.mkForce "/run/secrets/vars/forgejo-slotctl-ssh/id_ed25519";
                  };
                }
              ];
            };
            address = self.lib.hosts.${host};
            # Only a public key is needed for eval; never generate a fixture var.
            public = self.lib.vars.machine host "openssh" "ssh.id_ed25519.pub";
            server = ryza.extendModules {
              inherit specialArgs;
              modules = [{services.imperium.forgejoEphemeral.dispatcherPublicKeyFile = public;}];
            };
            cc = client.config;
            sc = server.config;
            internal = sc.services.imperium.forgejoEphemeral.internal;
            dispatcherVars = ["forgejo-ephemeral-ugalabugala" "forgejo-ephemeral-noosphere" "forgejo-slotctl-ssh"];
            keys = lib.subtractLists local.config.users.users.root.openssh.authorizedKeys.keys sc.users.users.root.openssh.authorizedKeys.keys;
            vmCreds = cfg: lib.filterAttrs (name: _: lib.hasPrefix "microvm-credentials-ryza-ci-" name) cfg.systemd.services;
            loads =
              lib.concatMap (unit: lib.toList (unit.serviceConfig.LoadCredential or []))
              (builtins.attrValues (builtins.removeAttrs sc.systemd.services (builtins.attrNames (vmCreds sc))));
            sopsNames = cfg: builtins.attrNames cfg.sops.secrets;
            template = cc.systemd.services."forgejo-ephemeral-dispatcher@";
            sandbox = template.serviceConfig;
            unit = cc.systemd.services."forgejo-ephemeral-dispatcher@ryza-eph-1";
            wrapper = cc.services.imperium.forgejoEphemeral.internal.sshClients.ryza;
            vars = cc.clan.core.vars.generators;
            cred = pattern: lib.any (lib.hasPrefix "${pattern}:");
            guest = sc.microvm.vms.ryza-eph-1.config.config;
            trustShare = lib.findFirst (share: share.tag == "ci-trust") null guest.microvm.shares;
          in
            assert !cc.microvm.host.enable && !(cc.services.imperium.forgejoRunner.enable or false);
            assert builtins.isString cc.system.build.toplevel.drvPath;
            assert cc.services.imperium.forgejoEphemeral.remoteDispatcher == fleet;
            assert sc.services.imperium.forgejoEphemeral.remoteDispatcher == fleet;
            assert !((cerberus.extendModules {inherit specialArgs;}).config.services.imperium.forgejoRunner.enable);
            assert (cerberus.extendModules {inherit specialArgs;}).config.clan.core.vars.generators ? ncps-signing-key;
            assert lib.all (var: builtins.hasAttr var vars) dispatcherVars;
            assert (vars ? nix-ci-signing-key) == trustedJobs && (vars ? ncps-upload-auth) == trustedJobs;
            assert lib.all (id: cred id sandbox.LoadCredential == trustedJobs) ["trusted-ci-signing-key" "trusted-ncps-netrc"];
            assert lib.all (path: builtins.elem path sandbox.InaccessiblePaths) ["-/run/secrets" "-/run/secrets.d" "-/var/lib/sops-nix" "-/etc/ssh"];
            assert sandbox.PrivateDevices
            && sandbox.ProtectKernelTunables
            && sandbox.ProtectKernelModules
            && sandbox.ProtectKernelLogs
            && sandbox.ProtectControlGroups
            && sandbox.SystemCallFilter == ["@system-service"];
            # Sources stay under the masked tree; PID 1 supplies private
            # copies via LoadCredential. Neither daemon opens the source paths.
            assert lib.all (entry: lib.hasInfix ":/run/secrets/" entry) (sandbox.LoadCredential ++ unit.serviceConfig.LoadCredential);
            assert lib.all (id: cred id sandbox.LoadCredential) [
              "forgejo-pat-ugalabugala"
              "forgejo-pat-noosphere"
            ];
            assert cred "slotctl-ssh-key" unit.serviceConfig.LoadCredential;
            assert lib.all (g: lib.hasInfix "read:repository" vars.${g}.prompts.token.description == trustedJobs)
            ["forgejo-ephemeral-ugalabugala" "forgejo-ephemeral-noosphere"];
            assert builtins.elem "multi-user.target" unit.wantedBy;
            assert builtins.elem "forgejo-ephemeral-dispatcher@ryza-eph-1.service" template.aliases;
            assert lib.hasInfix (builtins.unsafeDiscardStringContext "--ssh-command ${wrapper} ")
            (builtins.unsafeDiscardStringContext unit.serviceConfig.ExecStart);
            assert lib.hasSuffix (" --vm-deadline 11820" + lib.optionalString trustedJobs " --trusted-jobs") unit.serviceConfig.ExecStart;
            assert builtins.isString sc.system.build.toplevel.drvPath;
            assert !(sc.systemd.services ? "forgejo-ephemeral-dispatcher@ryza-eph-1");
            assert sc.services.imperium.forgejoRunner.enable && sc.services.imperium.sccache.enable;
            assert builtins.attrNames sc.microvm.vms == builtins.attrNames local.config.microvm.vms;
            assert lib.mapAttrs (_: u: u.script) (vmCreds sc)
            == lib.mapAttrs (_: u: u.script) (vmCreds local.config);
            assert lib.all (var: !(builtins.hasAttr var sc.clan.core.vars.generators)) dispatcherVars;
            assert sopsNames sc == builtins.filter (name: !(lib.hasInfix "forgejo-ephemeral-" name)) (sopsNames local.config);
            assert server.options.services.imperium.forgejoEphemeral.dispatcherPublicKeyFile.default
            == self.lib.vars.machine host "forgejo-slotctl-ssh" "id_ed25519.pub";
            assert !(lib.any (load: builtins.match ".*(forgejo-pat|ci-signing-key|ncps-upload-auth|ncps-netrc|slotctl-ssh-key).*" load != null) loads);
            assert internal.slotctlSlots.ryza-eph-1.deliver == trustedJobs;
            assert (trustShare != null) == trustedJobs;
            assert !trustedJobs
            || (trustShare.readOnly
              && trustShare.source == internal.slotctlSlots.ryza-eph-1.trust_dir
              && builtins.elem "ro" guest.fileSystems."/run/ci-trust".options);
            assert lib.length keys
            == 1
            && lib.hasPrefix ''command="'' (lib.head keys)
            && lib.hasInfix ''",restrict,from="${address}" ssh-ed25519 '' (lib.head keys); {
              inherit address wrapper;
              launcher = internal.remoteActions.ryza-eph-1;
              ssh = lib.getExe' client.pkgs.openssh "ssh";
              systemdRun = lib.getExe' server.pkgs.systemd "systemd-run";
            };
          cutover =
            ciDispatcher
            // {
              remote = true;
              trustedJobs = false;
            };
          default = fixture cutover;
          moved = fixture (cutover // {host = "terra";});
          trusted = fixture (cutover // {trustedJobs = true;});
          inherit (default) ssh;
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
          # Exercise the generated launcher without handing a job to PID 1.
          offlineSystemdRun = pkgs.writeShellScript "slotctl-systemd-run-offline" ''
            printf '%s\n' "$@"
          '';
          ryzaHostKey = lib.concatStringsSep " " (lib.take 2 (lib.splitString " " (lib.trim (builtins.readFile (self.lib.vars.machine "ryza" "openssh" "ssh.id_ed25519.pub")))));
        in
          assert trusted.wrapper == default.wrapper;
            pkgs.runCommand "forgejo-ephemeral-ssh" {} ''
              export CREDENTIALS_DIRECTORY="$TMPDIR/credentials"
              export RUNTIME_DIRECTORY="$TMPDIR/runtime"
              export SLOTCTL_TEST_COMMAND='--slot ryza-eph-1 observe'
              mkdir -p "$CREDENTIALS_DIRECTORY" "$RUNTIME_DIRECTORY"
              touch "$CREDENTIALS_DIRECTORY/slotctl-ssh-key"
              ${lib.concatMapStringsSep "\n" (client: ''
                substitute ${client.wrapper} ./slotctl-ssh \
                  --replace-fail ${client.ssh} ${offlineSsh}
                chmod +x ./slotctl-ssh
                ./slotctl-ssh "$SLOTCTL_TEST_COMMAND" > ssh-config
                grep -Fx 'hostname ${self.lib.hosts.ryza}' ssh-config
                grep -Fx 'bindaddress ${client.address}' ssh-config
                grep -Fx 'user root' ssh-config
                grep -Fx 'batchmode yes' ssh-config
                grep -Fx 'stricthostkeychecking true' ssh-config
                known_hosts=$(awk '$1 == "userknownhostsfile" { print $2 }' ssh-config)
                grep -Fx '${self.lib.hosts.ryza} ${ryzaHostKey}' "$known_hosts"
              '') [default moved]}
              substitute ${default.launcher} ./slotctl-launch \
                --replace-fail ${default.systemdRun} ${offlineSystemdRun} \
                --replace-fail /run/forgejo-slotctl "$TMPDIR"
              chmod +x ./slotctl-launch
              ./slotctl-launch --slot ryza-eph-1 observe > "$out"
              grep -Fx -- '--property=ReadWritePaths=/run/microvm-credentials/forgejo-ryza-eph-1 /var/lib/microvms/ryza-eph-1/job' "$out"
              grep -Fx -- '--property=Requires=install-microvm-ryza-eph-1.service forgejo-ephemeral-firewall.service' "$out"
              grep -Fx -- '--property=RestrictAddressFamilies=AF_UNIX' "$out"
              printf '%s\n' --slot ryza-eph-1 observe | diff - <(tail -n 3 "$out")
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
