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
            # Every name a guest pins must be a site on the guard, with Caddy's
            # one-label wildcards: `*.noosphere.uk` never serves s3.main.garage.….
            vhosts = guard.services.caddy.virtualHosts;
            siteNames = builtins.filter (name: name != "") (lib.concatMap (name:
              map (address: let
                bare = lib.removePrefix "https://" (lib.removePrefix "http://" address);
              in
                builtins.replaceStrings ["{$LAB_DOMAIN}"] ["ugalabugala.org"] (builtins.head (lib.splitString ":" bare)))
              (lib.splitString " " (builtins.replaceStrings [","] [" "] name)))
            (builtins.attrNames vhosts));
            served = pin:
              lib.any (site: let
                rest = lib.removePrefix "*" site;
                label = lib.removeSuffix rest pin;
              in
                site
                == pin
                || (lib.hasPrefix "*." site && lib.hasSuffix rest pin && label != "" && !(lib.hasInfix "." label)))
              siteNames;
            s3Site = vhosts."s3.main.garage.noosphere.uk" or null;
            egressInternal = internal.egress.ryza-eph-1;
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
            assert lib.all served (pins ++ lib.optionals egressOn trustedPins);
            # S3 on the guard only with trusted egress, and only for the trusted sources.
            assert (s3Site != null) == egressOn;
            assert !egressOn
            || (lib.hasPrefix "invoke stygies-access\n" s3Site.extraConfig
              && lib.hasInfix "@notTrustedCI not remote_ip ${self.lib.lan.ryza-eph-trusted}\nrespond @notTrustedCI 403\nreverse_proxy https://${self.lib.vips.traefik} {" s3Site.extraConfig
              && lib.hasInfix "tls_server_name {http.request.host}" s3Site.extraConfig);
            assert (sc.systemd.services ? "forgejo-ephemeral-trusted-egress-cleanup@ryza-eph-1") == egressOn;
            assert !egressOn || sc.systemd.services."forgejo-ephemeral-trusted-egress-cleanup@ryza-eph-1".unitConfig.StartLimitIntervalSec == 0;
            assert builtins.elem "conntrack-tools" (map (p: p.pname or "") sc.environment.systemPackages) == egressOn;
            assert (sc.systemd.network.networks."10-lan".networkConfig ? IPv4DuplicateAddressDetectionTimeoutSec) == egressOn;
            assert !egressOn
            || (egressUnit.bindsTo
              == ["microvm@ryza-eph-1.service"]
              && egressUnit.partOf == ["forgejo-ephemeral-firewall.service"]
              && egressUnit.unitConfig.ReloadPropagatedFrom == ["forgejo-ephemeral-firewall.service"]
              && egressUnit.after == ["microvm@ryza-eph-1.service" "forgejo-ephemeral-firewall.service"]
              && egressUnit.wantedBy == []
              && egressUnit.requiredBy == []
              && egressUnit.serviceConfig.Type == "notify"
              && egressUnit.serviceConfig.NotifyAccess == "all"
              && egressUnit.serviceConfig.ExecStopPost == egressUnit.serviceConfig.ExecStop
              && egressInternal.unit == egressName
              && egressInternal.cleanupUnit == "forgejo-ephemeral-trusted-egress-cleanup@ryza-eph-1"
              && egressInternal.rule == egressRule
              && lib.hasInfix "trusted-egress-preflight" (lib.last vmPre)); {
              inherit address wrapper egressOn;
              rule = egressRule;
              launcher = internal.remoteActions.ryza-eph-1;
              inherit (internal) forcedCommand;
              egress = lib.optionalAttrs egressOn egressInternal.scripts;
              tools = {
                iptables = lib.getExe' sc.networking.firewall.package "iptables";
                conntrack = lib.getExe' server.pkgs.conntrack-tools "conntrack";
                ip = lib.getExe' server.pkgs.iproute2 "ip";
                arping = lib.getExe' server.pkgs.iputils "arping";
                systemctl = lib.getExe' server.pkgs.systemd "systemctl";
                notify = lib.getExe' server.pkgs.systemd "systemd-notify";
                grep = lib.getExe' server.pkgs.gnugrep "grep";
              };
              ssh = lib.getExe' client.pkgs.openssh "ssh";
              systemdRun = lib.getExe' server.pkgs.systemd "systemd-run";
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
          # Stand-ins for the egress scripts' tools, substituted for their
          # store paths. iptables keeps the NAT rules in a file, one per line
          # as -I stored them; conntrack keeps flows in another.
          fakeTools = pkgs.runCommand "trusted-egress-fake-tools" {} ''
            mkdir -p "$out/bin"
            cat > "$out/bin/iptables" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'iptables %s\n' "$*" >> "$EGRESS_LOG"
            [[ "$1 $2 $3 $4" == "-w 5 -t nat" ]] || exit 2
            op=$5
            shift 5
            case "$op" in
              -C)
                [[ -z "''${EGRESS_CHECK_FAILS:-}" ]] || exit 4
                grep -qxF -- "$*" "$EGRESS_RULES"
                ;;
              -I)
                chain=$1
                shift 2
                printf '%s\n' "$chain $*" >> "$EGRESS_RULES"
                ;;
              -D)
                [[ -z "''${EGRESS_DELETE_FAILS:-}" ]] || exit 4
                line=$(grep -nxF -- "$*" "$EGRESS_RULES" | head -n 1 | cut -d: -f1)
                [[ -n "$line" ]] || exit 1
                sed -i "''${line}d" "$EGRESS_RULES"
                ;;
              -S)
                echo "-P POSTROUTING ACCEPT"
                sed 's/^/-A /' "$EGRESS_RULES"
                ;;
              *) exit 2 ;;
            esac
            EOF
            cat > "$out/bin/ip" <<'EOF'
            #!${pkgs.runtimeShell}
            if [[ "$*" == *monitor* ]]; then
              # Not logged: it runs beside the script.
              [[ -z "''${EGRESS_MONITOR:-}" ]] || printf '%s\n' "$EGRESS_MONITOR"
              exit 0
            fi
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
            case "$1" in
              -D)
                [[ -n "''${EGRESS_FLUSH_FAILS:-}" ]] || rm -f "$EGRESS_FLOWS"
                exit 1
                ;;
              -L)
                [[ -z "''${EGRESS_LIST_FAILS:-}" ]] || exit 1
                [[ ! -e "$EGRESS_FLOWS" ]] || cat "$EGRESS_FLOWS"
                ;;
            esac
            EOF
            cat > "$out/bin/systemctl" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'systemctl %s\n' "$*" >> "$EGRESS_LOG"
            case "$1 $2" in
              "show --property=ActiveState") echo "''${EGRESS_UNIT_STATE:-inactive}" ;;
              "show --property=Job") echo "''${EGRESS_UNIT_JOB:-}" ;;
              "stop "* | "reset-failed "*) ;;
              *) exit 2 ;;
            esac
            EOF
            cat > "$out/bin/notify" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'notify %s\n' "$*" >> "$EGRESS_LOG"
            EOF
            cat > "$out/bin/grep-broken" <<'EOF'
            #!${pkgs.runtimeShell}
            exit 2
            EOF
            cat > "$out/bin/launcher" <<'EOF'
            #!${pkgs.runtimeShell}
            printf '%s\n' "$@"
            EOF
            chmod +x "$out"/bin/*
          '';
          # The guard moved to Terra: guests' DNS, pins, filter exceptions and
          # the trusted rule follow; Cerberus's Caddy guard then refuses to evaluate.
          guardArgs = {
            ciDispatcher = cutover;
            ciSlots = egressSlots;
            ciGuard = "terra";
          };
          movedGuard = (ryza.extendModules {specialArgs = guardArgs;}).config;
          movedGuest = movedGuard.microvm.vms.ryza-eph-1.config.config;
          movedCerberus = (cerberus.extendModules {specialArgs = guardArgs;}).config;
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
          assert movedGuest.systemd.network.networks."10-uplink".dns == [self.lib.hosts.terra];
          assert movedGuest.networking.hosts ? ${self.lib.hosts.terra} && !(movedGuest.networking.hosts ? ${self.lib.hosts.cerberus});
          assert lib.hasInfix " -d ${self.lib.hosts.terra}/32 " movedGuard.services.imperium.forgejoEphemeral.internal.egress.ryza-eph-1.rule;
          assert lib.hasInfix "-d ${self.lib.hosts.terra} -p udp --dport 53 -j ACCEPT" movedGuard.systemd.services.forgejo-ephemeral-firewall.script;
          assert lib.any (check: !check.assertion && lib.hasPrefix ''The nix-eph egress guard (_ci-slots.nix guard = "terra")'' check.message) movedCerberus.assertions;
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

              # The egress unit's real scripts, their tools replaced by logging
              # stand-ins: the exact DAD probe, NAT rule, deletes and flushes.
              tool() {
                substitute "$1" "$2" \
                  --replace-fail ${egress.tools.iptables} ${fakeTools}/bin/iptables \
                  --replace-fail ${egress.tools.conntrack} ${fakeTools}/bin/conntrack \
                  --replace-fail ${egress.tools.ip} ${fakeTools}/bin/ip \
                  --replace-fail ${egress.tools.arping} ${fakeTools}/bin/arping \
                  --replace-fail ${egress.tools.systemctl} ${fakeTools}/bin/systemctl \
                  --replace-fail ${egress.tools.notify} ${fakeTools}/bin/notify
                chmod +x "$2"
              }
              tool ${egress.egress.egressStart} ./egress-start
              tool ${egress.egress.egressReload} ./egress-reload
              tool ${egress.egress.egressStop} ./egress-stop
              tool ${egress.egress.egressCleanup} ./egress-cleanup
              tool ${egress.egress.egressPreflight} ./egress-preflight
              export EGRESS_LOG="$TMPDIR/egress.log" EGRESS_RULES="$TMPDIR/egress.rules" EGRESS_FLOWS="$TMPDIR/egress.flows"
              fresh() {
                : > "$EGRESS_LOG"
                : > "$EGRESS_RULES"
                rm -f "$EGRESS_FLOWS"
              }
              refused() {
                if "$@" 2> refused.err; then
                  echo "allowed: $*" >&2
                  exit 1
                fi
              }
              rule='${egress.rule}'
              tail='${lib.removePrefix "POSTROUTING " egress.rule}'
              fresh
              ./egress-start 2> start.err
              ./egress-reload
              ./egress-stop
              cat > expected <<EOF
              ip -4 -o address show dev ens18 to ${self.lib.lan.ryza-eph-trusted}/32
              arping -q -D -c 2 -w 3 -I ens18 ${self.lib.lan.ryza-eph-trusted}
              iptables -w 5 -t nat -C $rule
              iptables -w 5 -t nat -S POSTROUTING
              iptables -w 5 -t nat -I POSTROUTING 1 $tail
              notify --ready
              iptables -w 5 -t nat -C $rule
              iptables -w 5 -t nat -D $rule
              iptables -w 5 -t nat -C $rule
              iptables -w 5 -t nat -S POSTROUTING
              iptables -w 5 -t nat -I POSTROUTING 1 $tail
              iptables -w 5 -t nat -C $rule
              iptables -w 5 -t nat -D $rule
              iptables -w 5 -t nat -C $rule
              iptables -w 5 -t nat -S POSTROUTING
              conntrack -D --orig-src 10.99.2.2 --reply-dst ${self.lib.lan.ryza-eph-trusted}
              conntrack -L --orig-src 10.99.2.2 --reply-dst ${self.lib.lan.ryza-eph-trusted}
              EOF
              diff expected "$EGRESS_LOG"
              [[ ! -s "$EGRESS_RULES" ]]
              # With no monitor output the watch ends at once, and with it the unit.
              grep -F 'trusted egress for ryza-eph-1 ends: ${self.lib.lan.ryza-eph-trusted} left ens18' start.err
              # The address leaving (a conflict after binding) ends it; others don't.
              fresh
              EGRESS_MONITOR='Deleted 2: ens18    inet ${self.lib.lan.ryza-eph}/32 scope global ens18
              Deleted 2: ens18    inet ${self.lib.lan.ryza-eph-trusted}/32 scope global ens18' ./egress-start 2> start.err
              [[ $(grep -c 'ends:' start.err) == 1 ]]
              # A duplicate address is a fixed refusal (exit 10), and nothing is inserted.
              fresh
              status=0
              EGRESS_ARPING=1 ./egress-start 2> conflict.err || status=$?
              [[ $status == 10 ]]
              grep -F 'another host answers ARP for ${self.lib.lan.ryza-eph-trusted} on ens18' conflict.err
              if grep -q -e '^iptables' -e '^notify' "$EGRESS_LOG"; then exit 1; fi
              status=0
              EGRESS_ARPING=2 ./egress-start 2> /dev/null || status=$?
              [[ $status == 1 && ! -s "$EGRESS_RULES" ]]
              # So is an address networkd dropped (exit 11), before any probe.
              fresh
              status=0
              EGRESS_NO_ADDRESS=1 ./egress-start 2> /dev/null || status=$?
              [[ $status == 11 ]]
              if grep -q -e '^arping' -e '^iptables' "$EGRESS_LOG"; then exit 1; fi

              # Fail closed. A clean table and an inactive unit boot; a failed,
              # active or queued unit doesn't, whatever its state.
              fresh
              ./egress-preflight
              for state in failed:"" active:"" activating:"" deactivating:"" inactive:42; do
                EGRESS_UNIT_STATE=''${state%%:*} EGRESS_UNIT_JOB=''${state#*:} refused ./egress-preflight
              done
              # ExecStop fails and leaves the rule: the next preflight refuses
              # even with the unit inactive; the cleanup removes it, then it boots.
              ./egress-start 2> /dev/null
              refused env EGRESS_DELETE_FAILS=1 ./egress-stop
              [[ -s "$EGRESS_RULES" ]]
              refused ./egress-preflight
              grep -F 'trusted NAT rule present' refused.err
              refused env EGRESS_DELETE_FAILS=1 ./egress-cleanup
              grep -F 'the slot stays unusable' refused.err
              ./egress-cleanup
              [[ ! -s "$EGRESS_RULES" ]]
              grep -Fx 'systemctl stop forgejo-ephemeral-trusted-egress@ryza-eph-1.service' "$EGRESS_LOG"
              grep -Fx 'systemctl reset-failed forgejo-ephemeral-trusted-egress@ryza-eph-1.service' "$EGRESS_LOG"
              ./egress-preflight
              # A rule in another form (an older generation's) is found by -S and removed.
              printf '%s\n' 'POSTROUTING -s 10.99.2.2/32 -o ens18 -j SNAT --to-source ${self.lib.lan.ryza-eph-trusted}' > "$EGRESS_RULES"
              refused ./egress-preflight
              grep -F 'a trusted NAT rule for 10.99.2.2 is present' refused.err
              ./egress-cleanup
              [[ ! -s "$EGRESS_RULES" ]]
              # A flow still NATed to the trusted source refuses the boot too.
              echo 'tcp 6 431999 ESTABLISHED src=10.99.2.2 dst=${self.lib.hosts.cerberus} sport=40000 dport=443' > "$EGRESS_FLOWS"
              refused env EGRESS_FLUSH_FAILS=1 ./egress-stop
              refused ./egress-preflight
              grep -F 'flows from 10.99.2.2 via ${self.lib.lan.ryza-eph-trusted} remain' refused.err
              refused env EGRESS_FLUSH_FAILS=1 ./egress-cleanup
              ./egress-cleanup
              ./egress-preflight
              # An unreadable table is never "absent": -C errors and -L failures refuse.
              EGRESS_CHECK_FAILS=1 refused ./egress-preflight
              EGRESS_LIST_FAILS=1 refused ./egress-preflight
              ./egress-start 2> /dev/null
              EGRESS_CHECK_FAILS=1 refused ./egress-stop
              [[ -s "$EGRESS_RULES" ]]
              ./egress-cleanup
              ./egress-preflight
              # A grep error is never "no other form present".
              for script in preflight cleanup; do
                substitute ./egress-$script ./egress-$script-badgrep --replace-fail ${egress.tools.grep} ${fakeTools}/bin/grep-broken
                chmod +x ./egress-$script-badgrep
                refused ./egress-$script-badgrep
              done
              ./egress-preflight
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
