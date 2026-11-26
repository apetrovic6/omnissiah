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
          fixture = fleet: slots: let
            inherit (fleet) host trustedJobs;
            specialArgs = {
              ciDispatcher = fleet;
              ciSlots = slots;
            };
            egressOn = slots.ryza.egress.trusted != null;
            # The guard's Caddy, wherever the dispatcher runs (README "Trusted slot egress").
            guard = (self.nixosConfigurations.${self.lib.ciGuard}.extendModules {inherit specialArgs;}).config;
            caddy = guard.services.caddy.extraConfig;
            pins = ["forge.ugalabugala.org" "ncps.noosphere.uk" "forge.noosphere.uk"];
            trustedPins = ["s3.main.garage.noosphere.uk" "harbor.noosphere.uk" "ntfy.ugalabugala.org"];
            untrustedMatcher = lib.concatStringsSep "\n" [
              "  @blockedEphemeral {"
              "    remote_ip ${self.lib.lan.ryza-eph}"
              "    not host forge.{$LAB_DOMAIN} ncps.noosphere.uk forge.noosphere.uk"
              "  }"
              "  respond @blockedEphemeral 403"
            ];
            trustedMatcher = lib.concatStringsSep "\n" [
              "  @blockedEphemeralTrusted {"
              "    remote_ip ${self.lib.lan.ryza-eph-trusted}"
              "    not host forge.{$LAB_DOMAIN} ncps.noosphere.uk forge.noosphere.uk s3.main.garage.noosphere.uk harbor.noosphere.uk ntfy.{$LAB_DOMAIN}"
              "  }"
              "  respond @blockedEphemeralTrusted 403"
            ];
            caddyNames =
              builtins.filter (name: name != "") (lib.splitString " " (builtins.replaceStrings ["{$LAB_DOMAIN}"] ["ugalabugala.org"]
                  (lib.removePrefix "    not host " (builtins.elemAt (lib.splitString "\n" trustedMatcher) 2))));
            egressName = "forgejo-ephemeral-trusted-egress@ryza-eph-1";
            egressUnit = sc.systemd.services.${egressName} or null;
            egressRule = "POSTROUTING -s 10.99.2.2/32 -d ${self.lib.hosts.cerberus}/32 -p tcp --dport 443 -o ens18 -j SNAT --to-source ${self.lib.lan.ryza-eph-trusted}";
            vmPre = sc.systemd.services."microvm@ryza-eph-1".serviceConfig.ExecStartPre;
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
            && lib.hasInfix ''",restrict,from="${address}" ssh-ed25519 '' (lib.head keys);
            # Trusted egress (PR 8). Off: no address, unit, rule, matcher or extra pins.
            assert (egressUnit != null) == egressOn;
            assert (internal.slotctlSlots.ryza-eph-1 ? trusted_egress) == egressOn;
            assert internal.slotctlSlots.ryza-eph-1.trusted_egress or true;
            assert (internal.egress.ryza-eph-1 != {}) == egressOn;
            assert sc.services.imperium.forgejoEphemeral.egressTrustedAddress
            == (
              if egressOn
              then self.lib.lan.ryza-eph-trusted
              else null
            );
            assert sc.systemd.network.networks."10-lan".address == local.config.systemd.network.networks."10-lan".address;
            assert sc.systemd.network.networks."10-lan".addresses
            == lib.optional egressOn {
              Address = "${self.lib.lan.ryza-eph-trusted}/32";
              DuplicateAddressDetection = "ipv4";
            };
            assert lib.hasInfix " --trusted-egress" unit.serviceConfig.ExecStart == egressOn;
            assert lib.hasSuffix (" --vm-deadline 11820" + lib.optionalString trustedJobs " --trusted-jobs" + lib.optionalString egressOn " --trusted-egress") unit.serviceConfig.ExecStart;
            assert lib.hasInfix untrustedMatcher caddy;
            assert lib.hasInfix "@blockedEphemeralTrusted" caddy == egressOn;
            assert !egressOn || lib.hasInfix "respond @blockedEphemeral 403\n\n${trustedMatcher}\n}" caddy;
            assert guest.networking.hosts.${self.lib.hosts.cerberus} == pins ++ lib.optionals egressOn trustedPins;
            assert lib.sort builtins.lessThan caddyNames == lib.sort builtins.lessThan (pins ++ trustedPins);
            assert lib.any (lib.hasInfix "trusted-egress-preflight") vmPre == egressOn;
            assert !egressOn
            || (egressUnit.bindsTo
              == ["microvm@ryza-eph-1.service"]
              && egressUnit.partOf == ["forgejo-ephemeral-firewall.service"]
              && egressUnit.unitConfig.ReloadPropagatedFrom == ["forgejo-ephemeral-firewall.service"]
              && egressUnit.after == ["microvm@ryza-eph-1.service" "forgejo-ephemeral-firewall.service"]
              && egressUnit.wantedBy == []
              && egressUnit.requiredBy == []
              && egressUnit.serviceConfig.Type == "oneshot"
              && egressUnit.serviceConfig.RemainAfterExit
              && internal.egress.ryza-eph-1
              == {
                unit = egressName;
                rule = egressRule;
              }); {
              inherit address wrapper egressOn;
              rule = egressRule;
              launcher = internal.remoteActions.ryza-eph-1;
              inherit (internal) forcedCommand;
              egress = lib.optionalAttrs egressOn {
                inherit (egressUnit.serviceConfig) ExecStart ExecReload ExecStop;
                preflight = lib.findFirst (lib.hasInfix "trusted-egress-preflight") null vmPre;
              };
              ssh = lib.getExe' client.pkgs.openssh "ssh";
              systemdRun = lib.getExe' server.pkgs.systemd "systemd-run";
              systemctl = lib.getExe' server.pkgs.systemd "systemctl";
            };
          cutover =
            ciDispatcher
            // {
              remote = true;
              trustedJobs = false;
            };
          inherit (self.lib) ciSlots;
          egressSlots = lib.recursiveUpdate ciSlots {ryza.egress.trusted = "ryza-eph-trusted";};
          default = fixture cutover ciSlots;
          moved = fixture (cutover // {host = "terra";}) ciSlots;
          trusted = fixture (cutover // {trustedJobs = true;}) ciSlots;
          # Trusted egress set, with trust off as live, on, and with the dispatcher on Terra.
          egress = fixture cutover egressSlots;
          egressTrusted = fixture (cutover // {trustedJobs = true;}) egressSlots;
          egressMoved = fixture (cutover // {host = "terra";}) egressSlots;
          egressRun = "eph-${lib.fixedWidthString 12 "0" "0"}-ryza-${lib.fixedWidthString 32 "a" "a"}";
          inherit (default) ssh;
          # Stand-ins on PATH for the egress unit's tools: they log their
          # arguments and keep one NAT rule's presence in a file.
          fakeTools = pkgs.runCommand "trusted-egress-fake-tools" {} ''
            mkdir -p "$out/bin"
            cat > "$out/bin/iptables" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'iptables %s\n' "$*" >> "$EGRESS_LOG"
            case "$4" in
              -C) [[ -e "$EGRESS_STATE" ]] ;;
              -I) touch "$EGRESS_STATE" ;;
              -D) rm "$EGRESS_STATE" ;;
              *) exit 2 ;;
            esac
            EOF
            cat > "$out/bin/ip" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'ip %s\n' "$*" >> "$EGRESS_LOG"
            [[ -n "''${EGRESS_NO_ADDRESS:-}" ]] || echo "2: ens18    inet ${self.lib.lan.ryza-eph-trusted}/32 scope global ens18"
            EOF
            cat > "$out/bin/arping" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'arping %s\n' "$*" >> "$EGRESS_LOG"
            exit "''${EGRESS_ARPING:-0}"
            EOF
            cat > "$out/bin/conntrack" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'conntrack %s\n' "$*" >> "$EGRESS_LOG"
            exit 1
            EOF
            cat > "$out/bin/systemctl" <<'EOF'
            #!${pkgs.runtimeShell}
            case "$2" in
              --property=ActiveState) echo "''${EGRESS_UNIT_STATE:-inactive}" ;;
              --property=Job) echo "''${EGRESS_UNIT_JOB:-}" ;;
              *) exit 2 ;;
            esac
            EOF
            cat > "$out/bin/launcher" <<'EOF'
            #!${pkgs.runtimeShell}
            printf '%s\n' "$@"
            EOF
            chmod +x "$out"/bin/*
          '';
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
          assert egress.wrapper == default.wrapper && egress.egressOn && egressTrusted.egressOn && egressMoved.egressOn;
          assert !(default.egressOn || moved.egressOn || trusted.egressOn);
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
              ./slotctl-launch --slot ryza-eph-1 egress trusted ${egressRun} > launch.out
              printf '%s\n' --slot ryza-eph-1 egress trusted ${egressRun} | diff - <(tail -n 5 launch.out)

              # The real forced command admits `egress trusted RUN`, and only that, under the new verb.
              ${lib.concatMapStringsSep "\n" (fixture: ''
                substitute ${fixture.forcedCommand} ./forced --replace-fail ${fixture.launcher} ${fakeTools}/bin/launcher
                chmod +x ./forced
                SSH_ORIGINAL_COMMAND='--slot ryza-eph-1 egress trusted ${egressRun}' ./forced > forced.out
                printf '%s\n' --slot ryza-eph-1 egress trusted ${egressRun} | diff - forced.out
                for command in 'egress ${egressRun}' 'egress untrusted ${egressRun}' 'egress trusted' \
                  'egress trusted none' 'egress trusted ${egressRun} x' 'expire ${egressRun}'; do
                  status=0
                  SSH_ORIGINAL_COMMAND="--slot ryza-eph-1 $command" ./forced > forced.out 2> forced.err || status=$?
                  if [[ $status != 2 || -s forced.out ]]; then
                    echo "forced command accepted: $command" >&2
                    exit 1
                  fi
                  grep -Fx invalid-request forced.err
                done
              '') [default egress]}

              # The egress unit's real scripts against logging stand-ins: the exact
              # DAD probe, NAT rule, its delete and the conntrack flush.
              export PATH="${fakeTools}/bin:$PATH" EGRESS_LOG="$TMPDIR/egress.log" EGRESS_STATE="$TMPDIR/egress.rule"
              rule='${lib.removePrefix "POSTROUTING " egress.rule}'
              ${egress.egress.ExecStart}
              ${egress.egress.ExecReload}
              ${egress.egress.ExecStop}
              cat > expected <<EOF
              ip -4 -o address show dev ens18 to ${self.lib.lan.ryza-eph-trusted}/32
              arping -q -D -c 2 -w 3 -I ens18 ${self.lib.lan.ryza-eph-trusted}
              iptables -w -t nat -C POSTROUTING $rule
              iptables -w -t nat -I POSTROUTING 1 $rule
              iptables -w -t nat -C POSTROUTING $rule
              iptables -w -t nat -D POSTROUTING $rule
              iptables -w -t nat -C POSTROUTING $rule
              iptables -w -t nat -I POSTROUTING 1 $rule
              iptables -w -t nat -C POSTROUTING $rule
              iptables -w -t nat -D POSTROUTING $rule
              iptables -w -t nat -C POSTROUTING $rule
              conntrack -D --orig-src 10.99.2.2 --reply-dst ${self.lib.lan.ryza-eph-trusted}
              conntrack -L --orig-src 10.99.2.2 --reply-dst ${self.lib.lan.ryza-eph-trusted}
              EOF
              diff expected "$EGRESS_LOG"
              [[ ! -e "$EGRESS_STATE" ]]
              # A duplicate address is a fixed refusal (exit 10), and nothing is inserted.
              : > "$EGRESS_LOG"
              status=0
              EGRESS_ARPING=1 ${egress.egress.ExecStart} 2> conflict.err || status=$?
              [[ $status == 10 ]]
              grep -F 'another host answers ARP for ${self.lib.lan.ryza-eph-trusted} on ens18' conflict.err
              if grep -q '^iptables' "$EGRESS_LOG" || [[ -e "$EGRESS_STATE" ]]; then exit 1; fi
              status=0
              EGRESS_ARPING=2 ${egress.egress.ExecStart} 2> /dev/null || status=$?
              [[ $status == 1 && ! -e "$EGRESS_STATE" ]]
              # So is an address networkd dropped (exit 11), before any probe.
              : > "$EGRESS_LOG"
              status=0
              EGRESS_NO_ADDRESS=1 ${egress.egress.ExecStart} 2> /dev/null || status=$?
              [[ $status == 11 ]]
              if grep -q -e '^arping' -e '^iptables' "$EGRESS_LOG"; then exit 1; fi
              # The VM preflight refuses while the unit is up or has a job queued.
              substitute ${lib.removePrefix "+" egress.egress.preflight} ./egress-preflight \
                --replace-fail ${egress.systemctl} ${fakeTools}/bin/systemctl
              chmod +x ./egress-preflight
              ./egress-preflight
              EGRESS_UNIT_STATE=failed ./egress-preflight
              for state in active:"" activating:"" deactivating:"" inactive:42; do
                if EGRESS_UNIT_STATE=''${state%%:*} EGRESS_UNIT_JOB=''${state#*:} ./egress-preflight 2> /dev/null; then
                  echo "VM preflight allowed egress unit state $state" >&2
                  exit 1
                fi
              done
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
