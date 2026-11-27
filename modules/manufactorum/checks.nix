{self, ...}: {
  perSystem = {
    pkgs,
    lib,
    self',
    system,
    ...
  }: let
    largeNodes = ["luna" "sol" "terra"];
    initial = import ../rites/_ci-slots.nix {
      takeover = false;
      nodes = {};
    };
    historical = initial // {hosts = lib.recursiveUpdate initial.hosts {ryza.egress.trusted = null;};};
    # Retirement deletes the real runner vars. Historical fixtures still
    # evaluate those units, using public synthetic UUIDs only when absent.
    runnerFixtureVars = machine: {
      clan.core.vars.generators =
        lib.genAttrs
        (builtins.filter (name: !builtins.pathExists "${self}/vars/per-machine/${machine}/${name}/uuid/value")
          ["forgejo-runner-ugalabugala" "forgejo-runner-noosphere"])
        (_: {files.uuid.value = lib.mkForce "00000000-0000-4000-8000-000000000001";});
    };
    fixtureRyza = self.nixosConfigurations.ryza.extendModules {
      specialArgs = {
        ciSlots = historical.hosts;
        ciNodes = historical.nodes;
      };
      modules = [(runnerFixtureVars "ryza")];
    };
    nodeData = name: state:
      import ../rites/_ci-slots.nix {
        takeover = true;
        takeoverLabels = ["nix-vm" "nix-eph"];
        ryzaSlots = 2;
        nodes.${name} = state;
      };
    nodeEval = machine: data: trustedJobs:
      (self.nixosConfigurations.${machine}.extendModules {
        specialArgs = {
          ciDispatcher = data.dispatcher // {inherit trustedJobs;};
          ciSlots = data.hosts;
          ciNodes = data.nodes;
        };
        modules = lib.optional (data.nodes.${machine}.hostRunnerEnabled or false) (runnerFixtureVars machine);
      }).config;
    nodeOn = name:
      nodeData name {
        hostRunnerEnabled = false;
        slotsEnabled = true;
        trustedEgress = true;
      };
    nodeHosts = lib.genAttrs largeNodes (node: nodeEval node (nodeOn node) true);
    nodeDispatchers = lib.genAttrs largeNodes (node: nodeEval self.lib.ciDispatcher.host (nodeOn node) true);
  in {
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
            (import ../rites/_forgejo-ephemeral-jobdir-test.nix {
              ryza = fixtureRyza;
              inherit nodeHosts;
            }))
        );
        forgejo-ephemeral-node-firewall = import ../rites/_forgejo-ephemeral-node-firewall-test.nix {inherit self pkgs lib;};
        forgejo-ephemeral-ssh = let
          inherit (self.nixosConfigurations) ryza cerberus;
          inherit (self.lib) ciDispatcher;
          local = fixtureRyza.extendModules {
            specialArgs.ciDispatcher =
              ciDispatcher
              // {
                remote = false;
                trustedJobs = false;
                takeover = false;
              };
          };
          fixture = fleet: slots: let
            inherit (fleet) host trustedJobs;
            specialArgs = {
              ciDispatcher = fleet;
              ciSlots = slots;
              # A bare-metal dispatcher still cannot keep its host runner.
              ciNodes =
                historical.nodes
                // lib.optionalAttrs (builtins.hasAttr host historical.nodes) {
                  ${host} =
                    historical.nodes.${host}
                    // {
                      hostRunnerEnabled = false;
                      untrustedTakeover = true;
                    };
                };
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
              modules = [(runnerFixtureVars "ryza") {services.imperium.forgejoEphemeral.dispatcherPublicKeyFile = public;}];
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
          # The nix-vm guests stay in every fixture here; the takeover has its own check.
          cutover =
            ciDispatcher
            // {
              remote = true;
              trustedJobs = false;
              takeover = false;
            };
          ciSlots = historical.hosts;
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
          assert lib.all (node: let
            server = nodeHosts.${node};
            client = nodeDispatchers.${node};
            slot = "${node}-eph-1";
            ssh = client.services.imperium.forgejoEphemeral.internal.sshClients.${node};
            exec = client.systemd.services."forgejo-ephemeral-dispatcher@${slot}".serviceConfig.ExecStart;
            authorized = server.users.users.root.openssh.authorizedKeys.keys;
          in
            lib.hasInfix (builtins.unsafeDiscardStringContext "--ssh-command ${ssh} ") (builtins.unsafeDiscardStringContext exec)
            && lib.any (lib.hasInfix ''",restrict,from="${self.lib.hosts.${self.lib.ciDispatcher.host}}" ssh-ed25519 '') authorized
            && !(server.clan.core.vars.generators ? forgejo-slotctl-ssh))
          largeNodes;
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
        forgejo-ephemeral-sccache = let
          inherit (self.lib) ciDispatcher sccacheCiKey;
          ciSlots = historical.hosts;
          fleet =
            ciDispatcher
            // {
              sccacheCi = true;
              trustedJobs = true;
              takeover = false;
            };
          slots = lib.recursiveUpdate ciSlots {ryza.egress.trusted = "ryza-eph-trusted";};
          activate.services.imperium.forgejoEphemeral.pools.ugalabugala.sccache.enable = true;
          withSecondPool = firstUsers: secondUsers:
            fixture fleet slots [
              activate
              {
                services.imperium.forgejoEphemeral.pools = {
                  ugalabugala.trust.users = lib.mkForce firstUsers;
                  noosphere-user = {
                    sccache.enable = true;
                    trust.users = secondUsers;
                    trust.repos."221" = {
                      owner = "manjo";
                      name = "auspex";
                    };
                  };
                };
              }
            ]
            fleet.host;
          fixture = fleet: slots: modules: host:
            (self.nixosConfigurations.${host}.extendModules {
              specialArgs = {
                ciDispatcher = fleet;
                ciSlots = slots;
                ciNodes = historical.nodes;
              };
              modules = modules ++ lib.optional (host == "ryza" && !fleet.takeover) (runnerFixtureVars host);
            }).config;
          source = "/run/secrets/vars/${sccacheCiKey.generatorName}/credentials";
          cc =
            fixture fleet slots [
              activate
              {clan.core.vars.generators.${sccacheCiKey.generatorName}.files.credentials.path = lib.mkForce source;}
            ]
            fleet.host;
          prepared = fixture fleet slots [] fleet.host;
          sc = fixture fleet slots [] "ryza";
          guest = sc.microvm.vms.ryza-eph-1.config.config;
          ordinaryGuest = self.nixosConfigurations.ryza.config.microvm.vms.ryza-eph-1.config.config;
          unit = "forgejo-ephemeral-dispatcher@";
          slotUnit = "${unit}ryza-eph-1";
          load = cfg: cfg.systemd.services.${unit}.serviceConfig.LoadCredential;
          exec = cfg: cfg.systemd.services.${slotUnit}.serviceConfig.ExecStart;
          generator = cfg: cfg.clan.core.vars.generators.${sccacheCiKey.generatorName} or null;
          config = cfg: cfg.services.imperium.forgejoEphemeral;
          vars = generator cc;
          failures = cfg: map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);
          expects = reason: cfg: lib.any (lib.hasInfix "sccache for pool ugalabugala requires ${reason}") (failures cfg);
          refusesSharedCache = cfg: lib.any (lib.hasInfix "sccache-enabled pools must have identical trust.users") (failures cfg);
          cache = import ../rites/_forgejo-ephemeral-sccache.nix {inherit lib pkgs;};
        in
          assert builtins.isString cc.system.build.toplevel.drvPath && builtins.isString sc.system.build.toplevel.drvPath;
          assert lib.subtractLists (load prepared) (load cc) == ["sccache-credentials:${source}"];
          assert lib.subtractLists (load cc) (load prepared) == [];
          # One dispatcher program with or without the pool opt-in (HOM-32 PR 12).
          assert lib.all (cfg:
            lib.hasInfix (builtins.unsafeDiscardStringContext " -I -B ${../rites/_forgejo-ephemeral-dispatcher.py} ")
            (builtins.unsafeDiscardStringContext (exec cfg))) [cc prepared];
          assert (config cc).pools.ugalabugala.sccache.enable;
          assert lib.all (pool: !(config cc).pools.${pool}.sccache.enable) ["noosphere-user" "noosphere-org"];
          assert vars.share && vars.files.credentials.secret && vars.files.credentials.owner == "root" && vars.files.credentials.mode == "0400";
          assert generator sc == null;
          assert !(ordinaryGuest.systemd.paths ? ci-sccache) && !(ordinaryGuest.systemd.services ? ci-sccache);
          assert guest.systemd.paths.ci-sccache.pathConfig.PathExists == "/run/ci-trust/sccache-credentials";
          assert lib.getName (lib.head guest.systemd.services.forgejo-one-job.path) == "sccache";
          assert expects "trusted egress" (fixture fleet ciSlots [activate] fleet.host);
          assert expects "dispatcher.sccacheCi" (fixture (fleet // {sccacheCi = false;}) slots [activate] fleet.host);
          assert expects "trustedJobs" (fixture (fleet // {trustedJobs = false;}) slots [activate] fleet.host);
          assert expects "trustedJobs" (fixture fleet slots [
              activate
              {services.imperium.forgejoEphemeral.pools.ugalabugala.trust.repos = lib.mkForce {};}
            ]
            fleet.host);
          assert expects "the remote dispatcher" (fixture (fleet // {remote = false;}) slots [activate] "ryza");
          assert !refusesSharedCache self.nixosConfigurations.${ciDispatcher.host}.config;
          assert !refusesSharedCache (withSecondPool ["manjo" "alice"] ["Alice" "Manjo"]);
          assert refusesSharedCache (withSecondPool ["manjo"] ["manjo" "alice"]);
            pkgs.testers.runNixOSTest {
              name = "forgejo-ephemeral-sccache";
              nodes.guest = {
                imports = [cache.guest];
                users.groups.forgejo-one-job = {};
                users.users.forgejo-one-job = {
                  isSystemUser = true;
                  group = "forgejo-one-job";
                };
                systemd.tmpfiles.rules = ["d /run/ci-trust 0700 root root - -"];
                systemd.timers.ci-sccache.wantedBy = lib.mkForce [];
              };
              testScript = ''
                guest.wait_for_unit("ci-sccache.path")
                source = "/run/ci-trust/sccache-credentials"
                target = "/run/ci-sccache/credentials"
                wrapper = "runuser -u forgejo-one-job -- ${lib.getExe cache.wrapper}"
                fixture = ${builtins.toJSON ("[default]\naws_access_key_id = GK" + lib.concatStrings (lib.replicate 12 "ab") + "\naws_secret_access_key = " + lib.concatStrings (lib.replicate 32 "cd") + "\n")}
                from shlex import quote
                publish = f"umask 077; printf %s {quote(fixture)} > {source}.tmp; mv {source}.tmp {source}"

                guest.succeed(f"test ! -e {target}")
                assert guest.succeed(f"{wrapper} ${lib.getExe' pkgs.coreutils "printf"} '%s' 'direct compile'") == "direct compile"
                guest.fail(f"{wrapper} --start-server")
                guest.fail("pgrep -u forgejo-one-job -x sccache")

                # Delivery wakes the path unit when an inotify event arrives.
                guest.succeed(publish)
                guest.wait_until_succeeds(f"cmp {source} {target}")
                assert guest.succeed(f"stat -c '%U:%G %a' {target}").strip() == "root:forgejo-one-job 440"
                guest.succeed(f"runuser -u forgejo-one-job -- test -r {target}")
                guest.fail(f"runuser -u forgejo-one-job -- test -r {source}")
                guest.fail(f"runuser -u forgejo-one-job -- chmod u+w {target}")
                guest.fail(f"runuser -u forgejo-one-job -- rm -f {target}")
                assert "sccache " in guest.succeed(f"{wrapper} --version")
                guest.succeed(f"rm {source}")
                guest.wait_until_succeeds(f"test ! -e {target}")

                # Without inotify (host-side virtiofs changes), the timer
                # still starts the watcher and it notices later delivery.
                guest.succeed("systemctl stop ci-sccache.path ci-sccache.service")
                guest.succeed("systemctl start ci-sccache.timer")
                guest.wait_for_unit("ci-sccache.service")
                guest.succeed(f"test ! -e {target}")
                guest.succeed(publish)
                guest.wait_until_succeeds(f"cmp {source} {target}")
                guest.succeed("systemctl stop ci-sccache.service")
                guest.succeed(f"test ! -e {target}")
              '';
            };
        # HOM-32 PR 12 (README "Ryza takeover"), evaluated with the gate on:
        # ryza's nix-vm guests and their CI credentials are gone, its std
        # slots serve the user pools' takeover labels, and the gate refuses
        # each missing precondition. Both label sets, with and without trust.
        forgejo-ephemeral-takeover = let
          data = args: let
            inventory = import ../rites/_ci-slots.nix ({
                takeover = true;
                takeoverLabels = ["nix-vm" "nix-eph"];
                ryzaSlots = 2;
                nodes = {};
              }
              // args);
          in
            inventory
            // {
              dispatcher =
                inventory.dispatcher
                // {
                  trustedJobs = false;
                  remote = true;
                  host = "cerberus";
                  sccacheCi = false;
                };
              hosts = lib.recursiveUpdate inventory.hosts {ryza.egress.trusted = null;};
            };
          on = data {};
          withNix = data {takeoverLabels = ["nix" "nix-vm" "nix-eph"];};
          withNixAck = data {
            takeoverLabels = ["nix" "nix-vm" "nix-eph"];
            untrustedTakeover = true;
          };
          threeSlots = data {
            takeoverLabels = ["nix" "nix-vm" "nix-eph"];
            ryzaSlots = 3;
          };
          off = data {takeover = false;};
          trusted = fleet: fleet // {trustedJobs = true;};
          egressOn = hosts: lib.recursiveUpdate hosts {ryza.egress.trusted = "ryza-eph-trusted";};
          pr11 = builtins.readFile ../../.forgejo/workflows/machines.yml;
          machinesYml = builtins.replaceStrings ["runs-on: nix-machines\n"] ["runs-on: nix\n"] pr11;
          eval = host: fleet: slots: workflow: modules:
            (self.nixosConfigurations.${host}.extendModules {
              specialArgs = {
                ciDispatcher = fleet;
                ciSlots = slots;
                ciNodes = historical.nodes;
                ciMachinesWorkflow = workflow;
              };
              inherit modules;
            }).config;
          failures = cfg: map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);
          refuses = reason: cfg: lib.any (lib.hasInfix reason) (failures cfg);
          clean = cfg: failures cfg == [] && builtins.isString cfg.system.build.toplevel.drvPath;
          # The PR 12 label flip leaves Machines on host runners even
          # before PR 11, when the workflow still used `nix`.
          sc = eval "ryza" on.dispatcher on.hosts machinesYml [];
          cc = eval "cerberus" on.dispatcher on.hosts machinesYml [];
          # `nix` taken with trust, trusted egress, PR 11 and 3 slots.
          sc3 = eval "ryza" (trusted threeSlots.dispatcher) (egressOn threeSlots.hosts) pr11 [];
          cc3 = eval "cerberus" (trusted threeSlots.dispatcher) (egressOn threeSlots.hosts) pr11 [];
          # The gate off, whatever the data file's defaults are.
          before = eval "ryza" off.dispatcher off.hosts null [(runnerFixtureVars "ryza")];
          retiredVMs = ["ryza-ci-ugalabugala" "ryza-ci-noosphere"];
          ciVars = ["forgejo-runner-ugalabugala" "forgejo-runner-noosphere" "nix-ci-signing-key" "ncps-upload-auth" "sccache-garage-key"];
          hasCiVar = cfg: lib.filter (var: cfg.clan.core.vars.generators ? ${var}) ciVars;
          guestUnits = cfg: builtins.filter (name: lib.any (vm: lib.hasSuffix vm name) retiredVMs) (builtins.attrNames cfg.systemd.services);
          poolsOf = cfg: cfg.services.imperium.forgejoEphemeral.pools;
          pools = poolsOf cc;
          sliceOf = cfg: name: cfg.systemd.slices.${name}.sliceConfig;
          hidden = cfg: slot: cfg.systemd.services."microvm@${slot}".serviceConfig.InaccessiblePaths;
          # A persistent nix-vm runner kept on ryza by hand.
          kept = eval "ryza" on.dispatcher on.hosts machinesYml [
            self.nixosModules.forgejo-runner-microvm
            self.nixosModules.sccache
            {
              services.imperium.forgejoRunner = {
                enable = true;
                isolation = "microvm";
                labels = ["nix-vm:host"];
                microvm.uplink = "ens18";
              };
            }
          ];
          machinesRefused = "so machines.yml must be readable and off";
          withMachines = fleet: workflow: eval "cerberus" fleet on.hosts workflow [];
          trustRefused = "taking `nix` requires dispatcher.trustedJobs";
          # Ryza-side checks for both slot counts.
          ryzaOk = cfg: slots:
            clean cfg
            && !(cfg.services.imperium.forgejoRunner.enable or false)
            && !(cfg.services.imperium.sccache.enable or false)
            && builtins.attrNames cfg.microvm.vms == slots
            && guestUnits cfg == []
            && hasCiVar cfg == []
            && !(lib.any (name: lib.any (var: lib.hasInfix var name) ciVars) (builtins.attrNames cfg.sops.secrets))
            && builtins.attrNames cfg.services.imperium.forgejoEphemeral.internal.slotctlSlots == slots
            # Each std slice is 2 vCPU / 5 GiB (L6 in the PR 12 review).
            && lib.all (slot: let
              index = cfg.services.imperium.forgejoEphemeral.inventory.ryza.slots.${slot}.index;
              slice = sliceOf cfg "forgejo-ephemeral${lib.optionalString (index != 1) (toString index)}";
            in
              slice.CPUQuota
              == "200%"
              && slice.MemoryMax == "5G"
              && cfg.systemd.network.networks ? "20-vm-eph-${toString index}"
              && cfg.microvm.vms.${slot}.config.config.systemd.network.networks."10-uplink".address == ["10.99.${toString (index + 1)}.2/24"])
            slots
            # The retired guests' state stays hidden from every slot until removed by hand.
            && lib.all (slot: lib.all (vm: lib.all (path: builtins.elem path (hidden cfg slot)) ["-/var/lib/microvms/${vm}" "-/run/microvm-credentials/${vm}"]) retiredVMs) slots;
          cerberusOk = cfg: slots: labels:
            clean cfg
            && lib.all (slot: cfg.systemd.services ? "forgejo-ephemeral-dispatcher@${slot}" && builtins.elem "forgejo-ephemeral-dispatcher@${slot}.service" cfg.systemd.services."forgejo-ephemeral-dispatcher@".aliases) slots
            && lib.all (pool: (poolsOf cfg).${pool}.labels == labels && (poolsOf cfg).${pool}.dispatch == "owner") ["ugalabugala" "noosphere-user"]
            && lib.all (pool: pool.maxSlots == lib.length slots && !(builtins.elem "nix-machines" pool.labels)) (builtins.attrValues (poolsOf cfg));
          stage = node:
            nodeEval node (nodeData node {
              hostRunnerEnabled = false;
              trustedEgress = true;
            })
            true;
          nodeCutover = node: let
            beforeNode = nodeEval node (nodeData node {}) false;
            staged = stage node;
            enabled = nodeHosts.${node};
            dispatcher = nodeDispatchers.${node};
            slot = "${node}-eph-1";
            baseFlags = beforeNode.services.rke2.extraFlags;
            rke2 = cfg: {
              units = lib.genAttrs ["rke2-server.service" "rke2-agent.service"] (name:
                if cfg.systemd.units ? ${name}
                then toString cfg.systemd.units.${name}.unit
                else null);
              registries = toString cfg.environment.etc."rancher/rke2/registries.yaml".source;
              kernel = toString cfg.system.build.kernel;
              flags = cfg.services.rke2.extraFlags;
            };
            units = cfg: builtins.attrNames cfg.systemd.units;
            serviceDelta = from: to: {
              removed = lib.subtractLists (units to) (units from);
              added = lib.subtractLists (units from) (units to);
              changed = builtins.filter (
                name: to.systemd.units ? ${name} && toString from.systemd.units.${name}.unit != toString to.systemd.units.${name}.unit
              ) (units from);
            };
            cutover = serviceDelta beforeNode staged;
            enrollment = serviceDelta staged enabled;
            refused = nodeEval node (nodeOn node) false;
            refusedOnDispatcher = nodeEval self.lib.ciDispatcher.host (nodeOn node) false;
            noEgress =
              nodeEval node (nodeData node {
                hostRunnerEnabled = false;
                slotsEnabled = true;
              })
              true;
            stagedWithoutTrust = nodeEval node (nodeData node {hostRunnerEnabled = false;}) false;
            ack =
              nodeEval node (nodeData node {
                hostRunnerEnabled = false;
                slotsEnabled = true;
                untrustedTakeover = true;
              })
              false;
            overlap = nodeEval node (nodeData node {slotsEnabled = true;}) true;
            internal = dispatcher.services.imperium.forgejoEphemeral.internal;
            load = path: builtins.fromJSON path.text;
            exec = name: builtins.unsafeDiscardStringContext dispatcher.systemd.services."forgejo-ephemeral-dispatcher@${name}".serviceConfig.ExecStart;
            uses = file: name: lib.hasInfix (builtins.unsafeDiscardStringContext "--pools ${file} ") (exec name);
            stdPools = load internal.poolsFile;
            largePools = load internal.largePoolsFile;
            mesh = nodeEval self.lib.ciGuard (nodeOn node) true;
            matcher = mesh.services.caddy.extraConfig;
            da = cfg: cfg.systemd.network.networks."40-enp1s0".addresses;
            addr = kind: self.lib.lan."${node}-eph${kind}";
            memory =
              if node == "luna"
              then 3
              else 4;
            gc = cfg: {
              inherit (cfg.nix.gc) automatic options;
              storeCache = cfg.services.imperium.forgejoRunner.storeCache;
              minFree = cfg.nix.settings.min-free or null;
              maxFree = cfg.nix.settings.max-free or null;
            };
          in
            assert lib.all clean [staged enabled dispatcher ack];
            assert lib.all (refuses "retiring ${node}'s host runner requires") [refused refusedOnDispatcher noEgress stagedWithoutTrust];
            assert refuses "large slots require hostRunnerEnabled = false" overlap;
            assert rke2 beforeNode == rke2 staged && rke2 staged == rke2 enabled;
            assert lib.last baseFlags == "--kubelet-arg=system-reserved=memory=${toString memory}Gi";
            assert !beforeNode.nix.gc.automatic && staged.nix.gc.automatic && gc staged == gc enabled;
            assert staged.services.imperium.forgejoRunner.storeCache == null;
            assert lib.all (name: builtins.elem name cutover.removed) ["forgejo-runner-ugalabugala.service" "forgejo-runner-noosphere.service" "nix-prune-generations.timer"];
            assert builtins.elem "nix-gc.timer" cutover.added;
            assert !staged.microvm.host.enable && builtins.attrNames enabled.microvm.vms == [slot];
            assert hasCiVar enabled == [] && !enabled.services.imperium.sccache.enable;
            assert da staged == da beforeNode;
            assert lib.all (kind:
              builtins.elem {
                Address = "${addr kind}/32";
                DuplicateAddressDetection = "ipv4";
              } (da enabled)) ["" "-trusted"];
            assert lib.all (kind: lib.hasInfix (addr kind) matcher) ["" "-trusted"];
            assert uses internal.poolsFile "ryza-eph-1" && uses internal.largePoolsFile slot;
            assert lib.all (name: stdPools.${name}.labels == ["nix-vm" "nix-eph"] && largePools.${name}.labels == ["nix" "nix-machines"]) ["ugalabugala" "noosphere-user"];
            assert largePools.noosphere-org == stdPools.noosphere-org;
            assert lib.mapAttrs (_: pool: removeAttrs pool ["labels"]) stdPools == lib.mapAttrs (_: pool: removeAttrs pool ["labels"]) largePools;
            assert largePools.ugalabugala.trust.repos."1".schedules; {
              inherit cutover enrollment;
              inherit (rke2 enabled) units registries kernel flags;
              gc = map gc [beforeNode staged enabled];
              toplevels = map (cfg: cfg.system.build.toplevel.drvPath) [beforeNode staged enabled];
              labels = {
                std = lib.mapAttrs (_: pool: pool.labels) stdPools;
                large = lib.mapAttrs (_: pool: pool.labels) largePools;
              };
            };
        in
          # The flake reads the same file; on adds slots and the retired guests.
          assert import ../rites/_ci-slots.nix {}
          == {
            dispatcher = self.lib.ciDispatcher;
            hosts = self.lib.ciSlots;
            guard = self.lib.ciGuard;
            nodes = self.lib.ciNodes;
            inherit (self.lib) sccacheCiKey;
          };
          assert !off.dispatcher.takeover && on.dispatcher.takeover;
          assert on.dispatcher == off.dispatcher // {takeover = true;} && on.guard == off.guard;
          # Defaults: the safer label set, no acknowledgement, two slots.
          assert on.dispatcher.takeoverLabels == ["nix-vm" "nix-eph"] && !on.dispatcher.untrustedTakeover;
          assert builtins.attrNames on.hosts.ryza.slots == ["ryza-eph-1" "ryza-eph-2"];
          assert builtins.attrNames threeSlots.hosts.ryza.slots == ["ryza-eph-1" "ryza-eph-2" "ryza-eph-3"];
          assert lib.mapAttrs (_: spec: spec.index) threeSlots.hosts.ryza.slots
          == {
            ryza-eph-1 = 1;
            ryza-eph-2 = 2;
            ryza-eph-3 = 3;
          };
          assert on.hosts.ryza.slots.ryza-eph-1 == off.hosts.ryza.slots.ryza-eph-1;
          assert on.hosts.ryza.legacyVMs == off.hosts.ryza.legacyVMs ++ retiredVMs;
          assert !(builtins.tryEval (data {ryzaSlots = 4;}).hosts.ryza.slots).success;
          # Gate off: the guests and their credentials are there.
          assert before.services.imperium.forgejoRunner.enable && before.services.imperium.sccache.enable;
          assert hasCiVar before == ciVars && guestUnits before != [];
          # Default flip with trust off: no trust requirement, PR 11 not needed.
          assert ryzaOk sc ["ryza-eph-1" "ryza-eph-2"];
          assert cerberusOk cc ["ryza-eph-1" "ryza-eph-2"] ["nix-vm" "nix-eph"];
          assert lib.mapAttrs (_: repo: "${repo.owner}/${repo.name}") pools.ugalabugala.trust.repos
          == {
            "1" = "manjo/omnissiah";
            "7" = "manjo/nopresh";
            "8" = "manjo/fishing";
            "9" = "manjo/rust-app-template";
            "30" = "manjo/pilot";
          };
          assert lib.mapAttrs (_: repo: "${repo.owner}/${repo.name}") pools.noosphere-user.trust.repos
          == {
            "188" = "manjo/mushroom-farmer";
            "221" = "manjo/auspex";
          };
          assert lib.all (pool: pools.${pool}.trust.users == ["manjo"] && !pools.${pool}.sccache.enable) ["ugalabugala" "noosphere-user"];
          assert lib.all (repo: !repo.schedules) (builtins.attrValues (pools.ugalabugala.trust.repos // pools.noosphere-user.trust.repos));
          assert pools.noosphere-org.labels == ["nix-eph"] && pools.noosphere-org.dispatch == "owner" && pools.noosphere-org.trust.repos == {};
          # Trust off later never needs a code edit: with the default labels
          # nothing to change; with `nix`, the acknowledgement alone.
          assert clean (eval "cerberus" (trusted on.dispatcher) (egressOn on.hosts) machinesYml []);
          assert ryzaOk sc3 ["ryza-eph-1" "ryza-eph-2" "ryza-eph-3"];
          assert cerberusOk cc3 ["ryza-eph-1" "ryza-eph-2" "ryza-eph-3"] ["nix" "nix-vm" "nix-eph"];
          assert lib.all (host: clean (eval host withNixAck.dispatcher withNixAck.hosts pr11 [])) ["ryza" "cerberus"];
          assert lib.all (host: refuses trustRefused (eval host withNix.dispatcher withNix.hosts pr11 [])) ["ryza" "cerberus"];
          assert lib.all (host: refuses trustRefused (eval host (trusted withNix.dispatcher) withNix.hosts pr11 [])) ["ryza" "cerberus"];
          assert lib.all (host: refuses trustRefused (eval host withNix.dispatcher (egressOn withNix.hosts) pr11 [])) ["ryza" "cerberus"];
          assert lib.all (host: clean (eval host (trusted withNix.dispatcher) (egressOn withNix.hosts) pr11 [])) ["ryza" "cerberus"];
          # Other preconditions.
          assert refuses "needs the remote dispatcher" (eval "ryza" (on.dispatcher // {remote = false;}) on.hosts machinesYml []);
          assert refuses "takeoverLabels must be" (eval "cerberus" (on.dispatcher // {takeoverLabels = ["nix"];}) on.hosts machinesYml []);
          assert refuses "retires ryza's persistent runner" kept;
          # machines.yml: on a served label, missing, or in a form the check can't read, is refused.
          assert refuses "it runs on nix" (withMachines withNixAck.dispatcher machinesYml);
          assert refuses "it runs on nix-vm" (withMachines on.dispatcher "jobs:\n  build:\n    runs-on: nix-vm # trial\n");
          assert refuses ".forgejo/workflows/machines.yml is missing" (withMachines on.dispatcher null);
          assert lib.all (workflow: refuses machinesRefused (withMachines withNixAck.dispatcher workflow)) [
            "jobs:\n  build:\n    runs-on: nix\r\n"
            "jobs:\n  build:\n    runs-on: [nix-machines]\n"
            "jobs:\n  build:\n    runs-on:\n      - nix-machines\n"
            "jobs:\n  build:\n    runs-on: >-\n      nix\n"
            "jobs:\n  build:\n    \"runs-on\": nix-machines\n"
            "jobs:\n  build:\n    'runs-on': nix-machines\n"
            "jobs:\n  build:\n    runs-on : nix\n"
            "jobs:\n  b: {runs-on: nix}\n"
            "x: &l nix\njobs:\n  build:\n    runs-on: *l\n"
            "x: &d\n  runs-on: nix\njobs:\n  build:\n    <<: *d\n"
            "jobs:\n  build:\n    \"run\\x73-on\": nix\n"
            "jobs:\n  build:\n    runs-on: \${{ matrix.label }}\n"
          ];
          assert clean (withMachines withNixAck.dispatcher "jobs:\n  build:\n    runs-on: nix-machines # PR 11\n    steps:\n      - run: echo hello\n");
          assert clean (withMachines withNixAck.dispatcher "jobs:\n  build:\n    - runs-on: nix-machines\n");
          assert clean (withMachines withNixAck.dispatcher "jobs:\r\n  build:\r\n    runs-on: nix-machines\r\n");
            pkgs.writeText "forgejo-ephemeral-takeover.json" (builtins.unsafeDiscardStringContext (builtins.toJSON {
              slots = builtins.attrNames sc.microvm.vms;
              pools =
                lib.mapAttrs (_: pool: {
                  inherit (pool) labels dispatch;
                  trusted = builtins.attrNames pool.trust.repos;
                })
                pools;
              nodes = lib.genAttrs largeNodes nodeCutover;
            }));
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
