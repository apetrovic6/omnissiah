{self, ...}: {
  flake.nixosModules.forgejo-runner-ephemeral = {
    config,
    lib,
    options,
    pkgs,
    ...
  }: let
    cfg = config.services.imperium.forgejoEphemeral;
    inherit (config.networking) hostName;
    # This machine's entry in the slot inventory (_ci-slots.nix), and its one slot.
    host = self.lib.ciSlots.${hostName} or null;
    slotNames = builtins.attrNames (host.slots or {});
    slot =
      if slotNames == []
      then throw "forgejoEphemeral: ${hostName} has no slot in modules/rites/_ci-slots.nix."
      else builtins.head slotNames;
    spec = host.slots.${slot};
    generator = "forgejo-ephemeral-ugalabugala";
    dispatch = "forgejo-ephemeral-dispatcher";
    forgeHost = "forge.${self.lib.lab.domain}";
    cacheHost = "ncps.noosphere.uk";
    # The forge account whose runners the dispatcher registers, and the one
    # label it serves (pools and label sets: HOM-32 PR 5).
    login = "manjo";
    label = "nix-eph";
    slotUser = "microvm-eph";
    slice = "forgejo-ephemeral.slice";
    vm = "microvm@${slot}";
    installer = "install-microvm-${slot}";
    # Root-only writes to current/booted and the virtiofsd working directory.
    # QEMU owns only its runtime data, never the parent used by root hooks.
    controlDir = "${config.microvm.stateDir}/${slot}";
    vmDir = "${controlDir}/job";
    credParent = "/run/microvm-credentials";
    credDir = "${credParent}/${slot}";
    credIds = ["runner-token" "runner-uuid" "job-handle"];
    # Trusted jobs (HOM-31): root-only host dir behind a second virtiofs share; see _forgejo-ephemeral-trusted.nix.
    trustDir = "${credParent}/${slot}-trust";
    repoName = "rust-app-template";
    overlay = "/nix/.rw-store";
    images = ["nix-store-overlay.img" "var.img"];
    # The link to the guest, numbered by the slot's index (_ci-slots.nix).
    tap = "vm-eph-${toString spec.index}";
    inherit (host) uplink;
    mac = "02:00:00:c1:00:${lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString (spec.index + 2)))}";
    subnet = "10.99.${toString (spec.index + 1)}";
    gateway = "${subnet}.1";
    address = "${subnet}.2";
    inherit (self.lib.hosts) cerberus;
    # Every untrusted boot of this host's slots leaves from this address.
    egress = self.lib.lan.${host.egress.untrusted};
    # Every other microVM's credentials and state, declared or left behind.
    otherVMs = builtins.filter (name: name != slot) (builtins.attrNames config.microvm.vms) ++ host.legacyVMs;
    persistentPaths =
      ["-/persist"]
      ++ lib.concatMap
      (name: ["-${credParent}/${name}" "-${config.microvm.stateDir}/${name}"])
      otherVMs;
    guard = "forgejo-ephemeral-firewall";
    outChain = "${hostName}-eph-out";
    inChain = "${hostName}-eph-in";
    nonPublic = [
      "0.0.0.0/8"
      "10.0.0.0/8"
      "100.64.0.0/10"
      "127.0.0.0/8"
      "169.254.0.0/16"
      "172.16.0.0/12"
      "192.0.0.0/24"
      "192.0.2.0/24"
      "192.88.99.0/24"
      "192.168.0.0/16"
      "198.18.0.0/15"
      "198.51.100.0/24"
      "203.0.113.0/24"
      "224.0.0.0/3"
    ];
    # Install outside the stock firewall/NAT chains. Their reload flushes
    # those chains non-atomically; this tap's restrictions must stay in force.
    guardScript = ''
      set -eu -o pipefail
      apply() {
        local cmd="$1" table="$2" hook
        shift 2
        local -a hooks=( "$@" ) words
        {
          printf '*%s\n' "$table"
          if [[ "$action" = start && "$cmd/$table" = iptables/filter ]]; then
            printf ':%s - [0:0]\n' ${outChain} ${inChain}
            cat <<'RULES'
      -F ${outChain}
      -F ${inChain}
      -A ${outChain} ! -s ${address} -j DROP
      -A ${outChain} ! -o ${uplink} -j DROP
      -A ${outChain} -m conntrack --ctstate INVALID -j DROP
      -A ${outChain} -d ${cerberus} -p udp --dport 53 -j ACCEPT
      -A ${outChain} -d ${cerberus} -p tcp --dport 53 -j ACCEPT
      -A ${outChain} -d ${cerberus} -p tcp --dport 443 -j ACCEPT
      ${lib.concatMapStringsSep "\n" (net: "-A ${outChain} -d ${net} -j DROP") nonPublic}
      -A ${outChain} -p tcp --dport 443 -j ACCEPT
      -A ${outChain} -j DROP
      -A ${inChain} -i ${uplink} -d ${address} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      -A ${inChain} -j DROP
      RULES
          fi
          for hook in "''${hooks[@]}"; do
            read -r -a words <<< "$hook"
            if "$cmd" -w -t "$table" -C "''${words[@]}" 2>/dev/null; then
              printf -- '-D %s\n' "$hook"
            fi
            if [[ "$action" = start ]]; then
              printf -- '-I %s\n' "$hook"
            fi
          done
          if [[ "$action" = stop && "$cmd/$table" = iptables/filter ]]; then
            for chain in ${outChain} ${inChain}; do
              if iptables -w -S "$chain" >/dev/null 2>&1; then
                printf -- '-F %s\n-X %s\n' "$chain" "$chain"
              fi
            done
          fi
          printf 'COMMIT\n'
        } | "$cmd-restore" --wait --noflush
      }
      apply_rules() {
        local action="$1"
        apply iptables nat 'POSTROUTING -s ${address}/32 -o ${uplink} -j SNAT --to-source ${egress}'
        apply ip6tables filter 'INPUT -i ${tap} -j DROP' 'OUTPUT -o ${tap} -j DROP' \
          'FORWARD -i ${tap} -j DROP' 'FORWARD -o ${tap} -j DROP'
        apply iptables filter 'INPUT -i ${tap} -j DROP' 'OUTPUT -o ${tap} -j DROP' \
          'FORWARD -i ${tap} -j ${outChain}' 'FORWARD -o ${tap} -j ${inChain}'
      }
    '';
    # Every directory a slot unit names as a mandatory namespace path, in
    # creation order (parents first). The eval check
    # (_forgejo-ephemeral-jobdir-test.nix) reads this list.
    slotDirs = [
      {
        path = controlDir;
        owner = "root";
        group = slotUser;
        mode = "0750";
      }
      {
        path = vmDir;
        owner = slotUser;
        group = slotUser;
        mode = "0700";
      }
      {
        path = credParent;
        owner = "root";
        group = "root";
        mode = "0755";
      }
    ];
    # The job's PATH besides nix. A superset of the host runners' toolset
    # (_ci-toolset.nix, asserted below) in its own order, which the unit
    # already has: reordering would change it for nothing.
    slotToolset = pkgs:
      with pkgs; [
        bash
        cacert
        cargo
        coreutils
        curl
        devenv
        diffutils
        gawk
        git
        gzip
        jq
        mold
        nodejs
        rustc
        stdenv.cc
        gnutar
        util-linux
      ];
    ciToolset = import ./_ci-toolset.nix;
    installLine = dir: ''"$install" -d -o ${dir.owner} -g ${dir.group} -m ${dir.mode} -- ${lib.escapeShellArg dir.path}'';
    # Refuses a pre-existing symlink. This is a check, not a race-free guard:
    # it relies on the writers of the microvm-owned state dir being trusted.
    prepareDirs = pkgs.writeShellScript "${slot}-prepare-dirs" ''
      set -eu
      for dir in ${lib.escapeShellArgs (map (dir: dir.path) slotDirs)}; do
        if [[ -L "$dir" ]]; then
          printf 'Refusing pre-existing symlink for slot directory: %s\n' "$dir" >&2
          exit 1
        fi
      done
      install=${lib.getExe' pkgs.coreutils "install"}
      ${lib.concatMapStringsSep "\n" installLine slotDirs}
    '';
    preflight = pkgs.writeShellScript "${slot}-preflight" ''
      set -eu
      # WorkingDirectory is optional so privileged stop hooks can clean a failed start.
      [[ . -ef ${lib.escapeShellArg vmDir} ]]
      for file in ${lib.escapeShellArgs (map (id: "${credDir}/${id}") credIds)}; do
        [[ -f "$file" && ! -L "$file" && -r "$file" && -s "$file" ]]
      done
      for file in ${lib.escapeShellArgs images}; do
        [[ ! -e "$file" && ! -L "$file" ]]
      done
    '';
    scrub = pkgs.writeShellScript "${slot}-scrub" ''
      set -eu
      if [[ ! -L ${lib.escapeShellArg controlDir} && ! -L ${lib.escapeShellArg vmDir} ]]; then
        ${lib.getExe' pkgs.coreutils "rm"} -f -- ${lib.escapeShellArgs (map (image: "${vmDir}/${image}") images)}
      fi
      if [[ ! -L ${credParent} && -d ${credDir} && ! -L ${credDir} ]]; then
        ${lib.getExe' pkgs.coreutils "rm"} -f -- ${lib.escapeShellArgs (map (id: "${credDir}/${id}") credIds)}
        # Even '+' commands get the unit's ReadWritePaths bind mounts, so a
        # listed directory is a mount point here (EBUSY). The slot no longer
        # lists credDir; if rmdir still fails, the dispatcher's scrub removes
        # it or reports unexpected files. Never fail the stop path on this.
        ${lib.getExe' pkgs.coreutils "rmdir"} -- ${credDir} \
          || printf 'Leaving %s for the dispatcher scrub\n' ${credDir} >&2
      fi
    '';
    guest = {
      config,
      pkgs,
      ...
    }: let
      stateDir = "/var/lib/forgejo-one-job";
      runnerConfig = (pkgs.formats.yaml {}).generate "forgejo-one-job.yml" {
        runner = {
          capacity = 1;
          timeout = "65m";
          envs = {
            TMPDIR = "${stateDir}/tmp";
            CARGO_HOME = "${stateDir}/cargo";
            CARGO_BUILD_JOBS = toString spec.vcpu;
          };
        };
        cache.enabled = false;
        host.workdir_parent = "${stateDir}/work";
      };
    in {
      networking = {
        hostName = slot;
        useNetworkd = true;
        useDHCP = false;
        enableIPv6 = false;
        hosts.${cerberus} = [forgeHost cacheHost];
      };
      systemd.network.networks."10-uplink" = {
        matchConfig.MACAddress = mac;
        address = ["${address}/24"];
        gateway = ["${gateway}"];
        dns = [cerberus];
        networkConfig.IPv6AcceptRA = false;
      };
      microvm = {
        hypervisor = "qemu";
        inherit (spec) vcpu;
        mem = spec.memory * 1024;
        balloon = true;
        virtiofsd.group = slotUser;
        # The upstream tap-up script hardcodes user microvm. Match its
        # vnet header and multi-queue flags, but attach this slot's UID.
        binScripts.tap-up = lib.mkForce ''
          set -euo pipefail
          if [ -e /sys/class/net/${tap} ]; then
            ${lib.getExe' pkgs.iproute2 "ip"} link delete ${tap}
          fi
          ${lib.getExe' pkgs.iproute2 "ip"} tuntap add name ${tap} mode tap user ${slotUser} vnet_hdr multi_queue
          ${lib.getExe' pkgs.iproute2 "ip"} link set ${tap} up
        '';
        shares = [
          {
            tag = "ro-store";
            socket = "${controlDir}/${slot}-virtiofs-ro-store.sock";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
            readOnly = true;
          }
        ];
        writableStoreOverlay = overlay;
        volumes = [
          {
            image = builtins.elemAt images 0;
            mountPoint = overlay;
            size = spec.overlay * 1024;
          }
          {
            image = builtins.elemAt images 1;
            mountPoint = "/var";
            size = spec.var * 1024;
          }
        ];
        interfaces = [
          {
            type = "tap";
            id = tap;
            inherit mac;
          }
        ];
        credentialFiles = lib.genAttrs credIds (id: "${credDir}/${id}");
      };
      nix.settings = {
        experimental-features = ["nix-command" "flakes"];
        build-dir = "${overlay}/builds";
        substituters = ["https://${cacheHost}"];
        trusted-public-keys = [(builtins.readFile (self.lib.vars.shared "ncps-signing-key" "ncps-signing-key.pub"))];
        max-jobs = 1;
        cores = spec.vcpu;
        # Collect below a fifth of the overlay free, up to half, as the
        # persistent CI guests do (forgejo-runner-microvm.nix).
        min-free = spec.overlay / 5 * 1024 * 1024 * 1024;
        max-free = spec.overlay / 2 * 1024 * 1024 * 1024;
      };
      users.groups.forgejo-one-job = {};
      users.users.forgejo-one-job = {
        isSystemUser = true;
        group = "forgejo-one-job";
        home = stateDir;
      };
      systemd.coredump.enable = false;
      systemd.services.forgejo-one-job = {
        description = "Run one addressed Forgejo job and power off";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        unitConfig = {
          RequiresMountsFor = ["/var" overlay];
          SuccessAction = "poweroff";
          FailureAction = "poweroff";
        };
        path = [config.nix.package] ++ slotToolset pkgs;
        serviceConfig = {
          Type = "exec";
          User = "forgejo-one-job";
          Group = "forgejo-one-job";
          StateDirectory = "forgejo-one-job";
          StateDirectoryMode = "0700";
          WorkingDirectory = stateDir;
          LoadCredential = credIds;
          Restart = "no";
          RuntimeMaxSec = "70min";
          TimeoutStopSec = "15s";
          NoNewPrivileges = true;
          LimitCORE = 0;
        };
        script = ''
          set -eu
          mkdir -p tmp cargo work
          uuid=$(cat "$CREDENTIALS_DIRECTORY/runner-uuid")
          handle=$(cat "$CREDENTIALS_DIRECTORY/job-handle")
          test -n "$uuid" && test -n "$handle" && test -s "$CREDENTIALS_DIRECTORY/runner-token"
          exec ${lib.getExe pkgs.forgejo-runner} --config ${runnerConfig} one-job \
            --url https://${forgeHost} --uuid "$uuid" --token-url 'file:$CREDENTIALS_DIRECTORY/runner-token' \
            --label ${label}:host --handle "$handle" --wait
        '';
      };
    };
  in {
    imports = [
      # A path module, so importing it here as well as in
      # forgejo-runner-microvm.nix loads it once.
      self.inputs.microvm.nixosModules.host
      # The CI credentials trusted jobs receive (_forgejo-ephemeral-trusted.nix enables them).
      self.nixosModules.ci-credentials
      (import ./_forgejo-ephemeral-trusted.nix {inherit cfg slot vm dispatch controlDir trustDir cacheHost;})
    ];

    options.services.imperium.forgejoEphemeral = {
      enable = lib.mkEnableOption "this machine's Forgejo one-job microVM slot from modules/rites/_ci-slots.nix";
      trustedJobs.enable = lib.mkEnableOption ''
        delivering the CI signing key and ncps upload netrc to jobs whose exact run is a manjo push,
        schedule or dispatch (HOM-31). The PAT then also needs read:repository.
        See _forgejo-ephemeral-trusted.nix for the rule and who can read what'';
      repoId = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Numeric Forgejo repository ID of manjo/rust-app-template, the only eligible repository.";
      };
      egressAddress = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = egress;
        defaultText = lib.literalExpression "self.lib.lan.\${self.lib.ciSlots.\${hostName}.egress.untrusted}";
        description = "The dedicated SNAT source of this host's slots. The host's uplink must carry it as a /32.";
      };
      internal = lib.mkOption {
        internal = true;
        readOnly = true;
        type = lib.types.attrs;
        default = {inherit slot slotDirs prepareDirs;};
        description = "The slot, its directories and the script that creates them, for the eval check.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.repoId != null;
          message = "forgejoEphemeral: set the numeric ID of manjo/rust-app-template.";
        }
        {
          # One dispatcher, one state file, one guard: a second slot would
          # race the first for the same job until the dispatchers can share
          # a queue (HOM-32 PR 4).
          assertion = host != null && builtins.length slotNames == 1;
          message = "forgejoEphemeral: give ${hostName} exactly one slot in modules/rites/_ci-slots.nix.";
        }
        {
          # 0 would collide with the persistent CI guests' 10.99.1 and MAC :02.
          assertion = host == null || slotNames == [] || (spec.index >= 1 && spec.index <= 253);
          message = "forgejoEphemeral: a slot index in modules/rites/_ci-slots.nix must be between 1 and 253.";
        }
        {
          # The guard installs iptables rules; it does not know nftables.
          assertion = config.networking.firewall.enable && !config.networking.nftables.enable;
          message = "forgejoEphemeral needs the iptables firewall (networking.firewall without nftables).";
        }
        {
          # Compared by outPath. The label rule (top of forgejo-runner.nix)
          # needs this once a slot shares a label with the host runners.
          assertion = lib.all (p: builtins.elem p (slotToolset pkgs)) (ciToolset pkgs);
          message = "forgejoEphemeral: the slot's PATH must carry the whole shared CI toolset (_ci-toolset.nix).";
        }
      ];
      clan.core.vars.generators.${generator} = {
        share = false;
        prompts.token = {
          description =
            if cfg.trustedJobs.enable
            then "Forgejo dispatcher PAT for manjo on forge.ugalabugala.org (Public only; write:user and read:repository)"
            else "Forgejo dispatcher PAT for manjo on forge.ugalabugala.org (Public only; write:user only)";
          type = "hidden";
        };
        files.token = {
          secret = true;
          owner = "root";
          group = "root";
          mode = "0400";
        };
        runtimeInputs = [pkgs.coreutils];
        script = ''
          cp "$prompts/token" "$out/token"
        '';
      };
      # Only hosts with an ephemeral root (ryza) have this option; elsewhere
      # /var/lib persists by itself.
      services = lib.optionalAttrs (options.services.imperium ? impermanence) {
        imperium.impermanence.directories = [
          {
            directory = "/var/lib/${dispatch}";
            user = "root";
            group = "root";
            mode = "0700";
          }
        ];
      };
      users.groups.${slotUser} = {};
      users.users.${slotUser} = {
        isSystemUser = true;
        group = slotUser;
        # No kvm group: /dev/kvm, /dev/vhost-net and /dev/net/tun are 0666 on
        # Ryza. Without it the slot can't write the microvm:kvm 0775 state
        # dir or the persistent guests' dirs, even outside its sandbox.
      };
      # tmpfiles refuses the owner transition from the microvm-owned state
      # directory to this root-owned slot ("unsafe path transition"), so the
      # installer creates controlDir and job/. Keep the upstream GC link.
      systemd.tmpfiles.settings."10-microvm".${controlDir} = lib.mkForce {};
      # Root-owned /run: tmpfiles accepts this one (the installer also makes it).
      systemd.tmpfiles.rules = ["d ${credParent} 0755 root root - -"];
      microvm.vms.${slot} = {
        autostart = false;
        restartIfChanged = false;
        config = {
          imports = [guest];
          system.stateVersion = config.system.stateVersion;
          # virtiofsd --readonly enforces this on the host; make the guest
          # mount flag truthful too. Last, so it overrides "defaults" (rw).
          fileSystems."/nix/.ro-store".options = lib.mkAfter ["ro"];
        };
      };
      systemd.network.networks."20-${tap}" = {
        matchConfig.Name = tap;
        address = ["${gateway}/24"];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        linkConfig.RequiredForOnline = "no";
      };
      # The guard owns forwarding and SNAT for this tap. Do not add it to
      # stock NAT: egress must not fall back to the host's normal source
      # address. Routing between the tap and the uplink still needs IPv4
      # forwarding; stock NAT (the persistent CI guests') turns it on too.
      boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = lib.mkDefault true;
      microvm.host.enable = true;
      # The guest's vCPUs, and its memory plus one GiB for QEMU and virtiofsd.
      systemd.slices.forgejo-ephemeral.sliceConfig = {
        CPUQuota = "${toString (spec.vcpu * 100)}%";
        MemoryMax = "${toString (spec.memory + 1)}G";
        MemorySwapMax = 0;
        IOWeight = 20;
      };
      systemd.services = {
        ${installer} = {
          unitConfig = {
            RequiresMountsFor = [config.microvm.stateDir];
            # Re-run before every VM, dispatcher and support-unit start, so
            # repeated manual restarts must not trip start-limit-hit.
            StartLimitIntervalSec = 0;
          };
          serviceConfig = {
            # Both the installer and its pre-start must be able to start with no slot directory.
            WorkingDirectory = lib.mkForce "/";
            ExecStartPre = ["+${prepareDirs}"];
          };
          script = lib.mkBefore ''
            cd -- ${lib.escapeShellArg controlDir}
          '';
        };
        ${guard} = {
          description = "Restrict traffic on the Forgejo one-job tap";
          after = ["firewall.service"];
          requires = ["firewall.service"];
          path = [config.networking.firewall.package pkgs.coreutils];
          reloadIfChanged = true;
          script = guardScript + "\napply_rules start\n";
          reload = guardScript + "\napply_rules start\n";
          preStop = guardScript + "\napply_rules stop\n";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
        ${dispatch} = {
          description = "Dispatch Forgejo jobs to Ryza's one-job slot";
          wantedBy = ["multi-user.target"];
          wants = ["network-online.target"];
          requires = ["${installer}.service" "${guard}.service"];
          after = ["network-online.target" "${installer}.service" "${guard}.service"];
          path = [pkgs.systemd];
          serviceConfig = {
            Type = "exec";
            ExecStart = lib.concatStringsSep " " ([
                (lib.getExe pkgs.python3)
                "-I -B ${./_forgejo-ephemeral-dispatcher.py}"
                "--slot ${slot} --machine ${hostName} --slot-user ${slotUser}"
                "--forge-host ${forgeHost} --login ${login} --label ${label}"
                "--repo-id ${toString cfg.repoId}"
                "--state-dir /var/lib/${dispatch} --vm-dir ${vmDir} --credential-dir ${credDir}"
              ]
              ++ lib.optional cfg.trustedJobs.enable "--trusted-jobs --repo ${repoName} --trust-dir ${trustDir}");
            LoadCredential = ["forgejo-pat:${config.clan.core.vars.generators.${generator}.files.token.path}"];
            StateDirectory = dispatch;
            StateDirectoryMode = "0700";
            RuntimeDirectory = dispatch;
            RuntimeDirectoryMode = "0700";
            RuntimeDirectoryPreserve = "yes";
            ProtectSystem = "strict";
            # The installer creates both before systemd builds this namespace.
            # An optional missing path would stay read-only until restart.
            ReadWritePaths = [credParent vmDir];
            ProtectHome = true;
            PrivateTmp = true;
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            InaccessiblePaths = persistentPaths;
            CapabilityBoundingSet = ["CAP_CHOWN" "CAP_FOWNER" "CAP_DAC_OVERRIDE"];
            UMask = "0077";
            Restart = "on-failure";
            RestartSec = "7s";
            LimitCORE = 0;
            NoNewPrivileges = true;
          };
        };
        ${vm} = {
          # A oneshot without RemainAfterExit: every start re-runs it.
          requires = ["${installer}.service"];
          bindsTo = ["${guard}.service"];
          after = ["${guard}.service"];
          serviceConfig = {
            Slice = slice;
            User = slotUser;
            Group = slotUser;
            # Optional, so namespace setup and chdir cannot fail before the
            # first ExecStartPre or in the '+' stop hooks; preflight checks it.
            # QEMU only reads the credentials (fw_cfg), so credDir is not
            # listed: its bind mount made the scrub's rmdir fail with EBUSY.
            WorkingDirectory = "-${vmDir}";
            ProtectSystem = "strict";
            ReadWritePaths = ["-${vmDir}"];
            ProtectHome = true;
            PrivateTmp = true;
            # The pre-created TAP carries frames via /dev/net/tun, not IP sockets.
            RestrictAddressFamilies = ["AF_UNIX"];
            IPAddressDeny = "any";
            InaccessiblePaths = persistentPaths;
            NoNewPrivileges = true;
            Restart = "no";
            RuntimeMaxSec = "75min";
            TimeoutStartSec = "90s";
            TimeoutStopSec = "30s";
            ExecStartPre = ["+${prepareDirs}" preflight];
            ExecStopPost = ["+${scrub}"];
            LimitCORE = 0;
          };
        };
        "microvm-set-booted@${slot}" = {
          overrideStrategy = "asDropin";
          requires = ["${installer}.service"];
          serviceConfig = {
            User = "root";
            Group = "root";
          };
        };
        "microvm-virtiofsd@${slot}" = {
          requires = ["${installer}.service"];
          serviceConfig = {
            Slice = slice;
            RestrictAddressFamilies = ["AF_UNIX"];
            IPAddressDeny = "any";
          };
        };
      };
    };
  };
}
