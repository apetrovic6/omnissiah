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
          inherit (self.nixosConfigurations) ryza;
          local = ryza.extendModules {
            modules = [{services.imperium.forgejoEphemeral.remoteDispatcher.enable = lib.mkForce false;}];
          };
          role = host: {
            services.imperium.forgejoEphemeral.remoteDispatcher =
              {enable = lib.mkForce true;}
              // lib.optionalAttrs (host != null) {host = lib.mkForce host;};
          };
          fixture = host: let
            source =
              self.nixosConfigurations.${
                if host == null
                then ryza.config.services.imperium.forgejoEphemeral.remoteDispatcher.host
                else host
              };
            client = source.extendModules {modules = [(role host)];};
            name = client.config.networking.hostName;
            address = self.lib.hosts.${name};
            # Only a public key is needed for eval; never generate a fixture var.
            public = self.lib.vars.machine name "openssh" "ssh.id_ed25519.pub";
            server = ryza.extendModules {
              modules = [(role host) {services.imperium.forgejoEphemeral.dispatcherPublicKeyFile = public;}];
            };
            cc = client.config;
            sc = server.config;
            internal = sc.services.imperium.forgejoEphemeral.internal;
            uploadVars = ["nix-ci-signing-key" "ncps-upload-auth"];
            dispatcherVars = ["forgejo-ephemeral-ugalabugala" "forgejo-ephemeral-noosphere" "forgejo-slotctl-ssh"];
            keys = lib.subtractLists local.config.users.users.root.openssh.authorizedKeys.keys sc.users.users.root.openssh.authorizedKeys.keys;
            loads = lib.concatMap (unit: lib.toList (unit.serviceConfig.LoadCredential or [])) (builtins.attrValues sc.systemd.services);
            template = cc.systemd.services."forgejo-ephemeral-dispatcher@";
            unit = cc.systemd.services."forgejo-ephemeral-dispatcher@ryza-eph-1";
            wrapper = cc.services.imperium.forgejoEphemeral.internal.sshClients.ryza;
            cred = pattern: lib.any (lib.hasPrefix "${pattern}:");
            guest = sc.microvm.vms.ryza-eph-1.config.config;
            trustShare = lib.findFirst (share: share.tag == "ci-trust") null guest.microvm.shares;
          in
            assert !cc.microvm.host.enable;
            assert builtins.isString cc.system.build.toplevel.drvPath;
            assert lib.all (var: builtins.hasAttr var cc.clan.core.vars.generators) (uploadVars ++ dispatcherVars);
            assert lib.all (id: cred id template.serviceConfig.LoadCredential) [
              "trusted-ci-signing-key"
              "trusted-ncps-netrc"
              "forgejo-pat-ugalabugala"
              "forgejo-pat-noosphere"
            ];
            assert cred "slotctl-ssh-key" unit.serviceConfig.LoadCredential;
            assert builtins.elem "multi-user.target" unit.wantedBy;
            assert builtins.elem "forgejo-ephemeral-dispatcher@ryza-eph-1.service" template.aliases;
            assert lib.hasInfix (builtins.unsafeDiscardStringContext "--ssh-command ${wrapper} ")
            (builtins.unsafeDiscardStringContext unit.serviceConfig.ExecStart);
            assert lib.hasSuffix " --vm-deadline 11820 --trusted-jobs" unit.serviceConfig.ExecStart;
            assert builtins.isString sc.system.build.toplevel.drvPath;
            assert !(sc.systemd.services ? "forgejo-ephemeral-dispatcher@ryza-eph-1");
            assert builtins.attrNames sc.microvm.vms == ["ryza-eph-1"];
            assert lib.all (var: !(builtins.hasAttr var sc.clan.core.vars.generators)) (uploadVars ++ dispatcherVars);
            assert server.options.services.imperium.forgejoEphemeral.dispatcherPublicKeyFile.default
            == self.lib.vars.machine name "forgejo-slotctl-ssh" "id_ed25519.pub";
            assert !(lib.any (load: builtins.match ".*(forgejo-pat|ci-signing-key|ncps-upload-auth|ncps-netrc|slotctl-ssh-key).*" load != null) loads);
            assert trustShare != null && trustShare.readOnly && trustShare.source == internal.slotctlSlots.ryza-eph-1.trust_dir;
            assert internal.slotctlSlots.ryza-eph-1.deliver && builtins.elem "ro" guest.fileSystems."/run/ci-trust".options;
            assert lib.length keys
            == 1
            && lib.hasPrefix ''command="'' (lib.head keys)
            && lib.hasInfix ''",restrict,from="${address}" ssh-ed25519 '' (lib.head keys); {
              inherit address wrapper;
              launcher = internal.remoteActions.ryza-eph-1;
              ssh = lib.getExe' client.pkgs.openssh "ssh";
              systemdRun = lib.getExe' server.pkgs.systemd "systemd-run";
            };
          default = fixture null;
          moved = fixture "terra";
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
