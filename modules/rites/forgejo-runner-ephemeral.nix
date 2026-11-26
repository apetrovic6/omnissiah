{self, ...}: {
  flake.nixosModules.forgejo-runner-ephemeral = {
    config,
    lib,
    options,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption types;
    cfg = config.services.imperium.forgejoEphemeral;
    inherit (config.networking) hostName;
    inventory = cfg.inventory;
    host = inventory.${hostName} or {};
    dispatcherFor = machine: entry: entry.dispatcher or machine;
    sourceDispatcher = dispatcherFor hostName host;
    localSlots = lib.mapAttrs mkSlot (host.slots or {});
    hosted = localSlots != {};
    serves = lib.concatMapAttrs (machine: entry:
      lib.optionalAttrs (dispatcherFor machine entry == hostName) (
        lib.mapAttrs (_: _: machine) entry.slots
      ))
    inventory;
    dispatcherNames = lib.mapAttrsToList (slot: _: "${dispatch}@${slot}") serves;
    dispatching = serves != {};
    remoteClient = lib.any (machine: machine != hostName) (builtins.attrValues serves);
    remoteServer = hosted && sourceDispatcher != hostName;
    sshGenerator = "forgejo-slotctl-ssh";
    dispatch = "forgejo-ephemeral-dispatcher";
    forgeHosts = {
      ugalabugala = "forge.ugalabugala.org";
      noosphere = "forge.noosphere.uk";
    };
    cacheHost = "ncps.noosphere.uk";
    credParent = "/run/microvm-credentials";
    runRoot = "/run/forgejo-ephemeral";
    claims = "${runRoot}/claims";
    lockRoot = "/run/forgejo-slotctl";
    poolNamePattern = "[a-z][a-z0-9-]{0,62}";
    forgejoLogin = types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]{0,39}";
    forgejoRepoName = types.addCheck (types.strMatching "[A-Za-z0-9._-]{1,100}") (name: name != "." && name != "..");
    pools = builtins.attrValues cfg.pools;
    # Keep the existing guest and VM units byte-identical on the pilot.
    # Remote slots and any other label/forge selection need boot credentials.
    fixedPilot =
      !remoteServer
      && lib.length pools == 1
      && (builtins.head pools).forge == "ugalabugala"
      && (builtins.head pools).labels == ["nix-eph"];
    userPools = builtins.filter (pool: pool.scope ? user) pools;
    allUnique = values: lib.length values == lib.length (lib.unique values);
    # All scopes on a forge share one PAT. A user scope determines its
    # account; with only org scopes the operator account is manjo.
    forgeSettings = lib.genAttrs (lib.unique (map (pool: pool.forge) pools)) (forge: let
      userPool = lib.findFirst (pool: pool.forge == forge) null userPools;
    in {
      login =
        if userPool == null
        then "manjo"
        else userPool.scope.user;
      hasOrg = lib.any (pool: pool.forge == forge && pool.scope ? org) pools;
      generator = "forgejo-ephemeral-${forge}";
      credential = "forgejo-pat-${forge}";
    });
    poolsFile = pkgs.writeText "${hostName}-forgejo-ephemeral-pools.json" (builtins.toJSON (
      lib.mapAttrs (_: pool: {
        inherit (pool) forge scope labels dispatch maxSlots trust;
        host = forgeHosts.${pool.forge};
        inherit (forgeSettings.${pool.forge}) login;
      })
      cfg.pools
    ));
    poolAssertions = lib.concatLists (lib.mapAttrsToList (name: pool: let
        scopeKind =
          if pool.scope ? user
          then "user"
          else "org";
        validScope = builtins.attrNames pool.scope == [scopeKind];
      in [
        {
          assertion = builtins.match poolNamePattern name != null;
          message = "forgejoEphemeral: name of pool ${name} must match ${poolNamePattern}.";
        }
        {
          assertion = validScope;
          message = "forgejoEphemeral: pool ${name} must name exactly one user or org in scope.";
        }
        {
          assertion = pool.labels != [] && allUnique pool.labels;
          message = "forgejoEphemeral: pool ${name} must have a nonempty list of unique labels.";
        }
        {
          assertion =
            !validScope
            || lib.all (id:
              builtins.match "[1-9][0-9]*" id
              != null
              && lib.toLower pool.trust.repos.${id}.owner == lib.toLower pool.scope.${scopeKind})
            (builtins.attrNames pool.trust.repos);
          message = "forgejoEphemeral: trusted repos for pool ${name} must use canonical positive numeric IDs and belong to the scope owner.";
        }
        {
          # Without users the allowlist would still trust every writer's schedules.
          assertion = pool.trust.repos == {} || pool.trust.users != [];
          message = "forgejoEphemeral: pool ${name} lists trusted repos, so trust.users must not be empty.";
        }
        {
          assertion =
            pool.dispatch
            == "owner"
            || lib.all (id: builtins.match "[1-9][0-9]*" id == null || builtins.elem (lib.toInt id) pool.dispatch) (builtins.attrNames pool.trust.repos);
          message = "forgejoEphemeral: every trusted repo of pool ${name} must also be in its dispatch list.";
        }
      ])
      cfg.pools);
    inherit (self.lib.hosts) cerberus;
    allSlotNames = lib.concatMap (entry: builtins.attrNames entry.slots) (builtins.attrValues inventory);
    # The live pilot keeps its fw_cfg paths. New/remote slots have their own
    # writable credential parent, including the root-only slot run marker.
    slotCredentials = slot:
      if hostName == "ryza" && slot == "ryza-eph-1" && !remoteServer
      then credParent
      else "${credParent}/forgejo-${slot}";
    # Hide both parts of each other microVM, including stopped legacy guests.
    inaccessibleVMs = slot:
      ["-/persist"]
      ++ lib.concatMap (name: let
        local = builtins.hasAttr name localSlots;
        credentials =
          if local
          then slotCredentials name
          else credParent;
      in
        [
          "-${credentials}/${name}"
          "-${config.microvm.stateDir}/${name}"
        ]
        ++ lib.optional local "-${credentials}/${name}-trust"
        ++ lib.optional (credentials != credParent) "-${credentials}")
      (builtins.filter (name: name != slot) (builtins.attrNames config.microvm.vms ++ (host.legacyVMs or [])));
    slotCapabilities = ["CAP_CHOWN" "CAP_FOWNER" "CAP_DAC_OVERRIDE"];
    commonSandbox = {
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      UMask = "0077";
      LimitCORE = 0;
      NoNewPrivileges = true;
    };
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
    slotClasses = {
      std = {
        overlayGiB = 50;
        runnerMinutes = 180;
      };
      large = {
        overlayGiB = 150;
        runnerMinutes = 360;
      };
    };
    pickupSeconds = 5 * 60;
    reportingMarginMinutes = 5;
    vmStartSeconds = 90;
    vmStopSeconds = 30;
    classFor = spec: let
      class = slotClasses.${spec.class} or (throw "forgejoEphemeral: unknown slot class ${spec.class}.");
      guestMinutes = class.runnerMinutes + pickupSeconds / 60 + reportingMarginMinutes;
    in
      class
      // {
        inherit guestMinutes;
        hostMinutes = guestMinutes + 5;
      };
    mkSlot = slot: spec: let
      class = classFor spec;
      # Keep index 1's names. Later slices are siblings, not children of
      # forgejo-ephemeral.slice (which has its own quota).
      suffix = lib.optionalString (spec.index != 1) "-${toString spec.index}";
      slotUser = "microvm-eph${suffix}";
      sliceName = "forgejo-ephemeral${lib.optionalString (spec.index != 1) (toString spec.index)}";
      slice = "${sliceName}.slice";
      vm = "microvm@${slot}";
      installer = "install-microvm-${slot}";
      # Root-only writes to current/booted and the virtiofsd working directory.
      # QEMU owns only its runtime data, never the parent used by root hooks.
      controlDir = "${config.microvm.stateDir}/${slot}";
      vmDir = "${controlDir}/job";
      credentials = slotCredentials slot;
      credDir = "${credentials}/${slot}";
      credIds = ["runner-token" "runner-uuid" "job-handle"] ++ lib.optionals (!fixedPilot) ["forgejo-url" "runner-label"];
      # Root-only host dir behind a second virtiofs share (HOM-31).
      trustDir = "${credentials}/${slot}-trust";
      overlay = "/nix/.rw-store";
      images = ["nix-store-overlay.img" "var.img"];
      # The link to the guest, numbered by the slot's index (_ci-slots.nix).
      tap = "vm-eph-${toString spec.index}";
      inherit (host) uplink;
      mac = "02:00:00:c1:00:${lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString (spec.index + 2)))}";
      subnet = "10.99.${toString (spec.index + 1)}";
      gateway = "${subnet}.1";
      address = "${subnet}.2";
      egress = cfg.egressAddress;
      persistentPaths = inaccessibleVMs slot;
      guard = "forgejo-ephemeral-firewall${suffix}";
      outChain = "${hostName}-eph-out${suffix}";
      inChain = "${hostName}-eph-in${suffix}";
      dependencies = ["${installer}.service" "${guard}.service"];
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
      slotDirs =
        [
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
        ]
        ++ lib.optional (credentials != credParent) {
          path = credentials;
          owner = "root";
          group = "root";
          mode = "0755";
        };
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
      slotctlEntry = {
        vm_dir = vmDir;
        credential_dir = credDir;
        # Cleanup still needs this path when delivery is disabled.
        trust_dir = trustDir;
        deliver = cfg.trustedJobs.enable;
        fixed_pilot = fixedPilot;
        user = slotUser;
        group = slotUser;
        min_free_bytes = (class.overlayGiB + spec.var + 10) * 1024 * 1024 * 1024;
      };
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
        if [[ ! -L ${credParent}${lib.optionalString (credentials != credParent) " && ! -L ${credentials}"} && -d ${credDir} && ! -L ${credDir} ]]; then
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
        pickupRunner = pkgs.forgejo-runner.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./_forgejo-runner-wait-timeout.patch];
        });
        urlArg =
          if fixedPilot
          then "https://${forgeHosts.ugalabugala}"
          else ''"$url"'';
        labelArg =
          if fixedPilot
          then "nix-eph:host"
          else ''"$label:host"'';
        checkCredentials =
          if fixedPilot
          then ''test -n "$uuid" && test -n "$handle" && test -s "$CREDENTIALS_DIRECTORY/runner-token"''
          else ''
            url=$(cat "$CREDENTIALS_DIRECTORY/forgejo-url")
            label=$(cat "$CREDENTIALS_DIRECTORY/runner-label")
            [[ -n "$uuid" && -n "$handle" && -n "$url" && -n "$label" && -s "$CREDENTIALS_DIRECTORY/runner-token" ]]'';
        runnerConfig = (pkgs.formats.yaml {}).generate "forgejo-one-job.yml" {
          runner = {
            capacity = 1;
            timeout = "${toString class.runnerMinutes}m";
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
          hosts.${cerberus} = [forgeHosts.ugalabugala cacheHost] ++ lib.optional (!fixedPilot) forgeHosts.noosphere;
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
              size = class.overlayGiB * 1024;
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
          min-free = class.overlayGiB / 5 * 1024 * 1024 * 1024;
          max-free = class.overlayGiB / 2 * 1024 * 1024 * 1024;
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
            SuccessExitStatus = [2]; # Bounded pickup expired without a task.
            RuntimeMaxSec = "${toString class.guestMinutes}min";
            TimeoutStopSec = "15s";
            NoNewPrivileges = true;
            LimitCORE = 0;
          };
          script = ''
            set -eu
            mkdir -p tmp cargo work
            uuid=$(cat "$CREDENTIALS_DIRECTORY/runner-uuid")
            handle=$(cat "$CREDENTIALS_DIRECTORY/job-handle")
            ${checkCredentials}
            exec ${lib.getExe pickupRunner} --config ${runnerConfig} one-job \
              --url ${urlArg} --uuid "$uuid" --token-url 'file:$CREDENTIALS_DIRECTORY/runner-token' \
              --label ${labelArg} --handle "$handle" --wait-timeout ${toString pickupSeconds}s
          '';
        };
      };
      sandbox = {
        # The installer and tmpfiles finish before systemd builds the namespace.
        ReadWritePaths = [credentials vmDir];
        InaccessiblePaths = persistentPaths;
        CapabilityBoundingSet = slotCapabilities;
      };
      remoteProperties =
        commonSandbox
        // sandbox
        // {
          RestrictAddressFamilies = ["AF_UNIX"];
          IPAddressDeny = "any";
          User = "root";
          Group = "root";
          RuntimeMaxSec = "95s";
          TimeoutStopSec = "5s";
          Requires = dependencies;
          After = dependencies ++ ["systemd-tmpfiles-setup.service"];
        };
      remoteAction = pkgs.writeShellScript "${slot}-remote-slotctl" ''
        umask 077
        # Refuse overlapping requests before submitting to PID 1. The inner
        # slotctl lock also covers subprocesses if this SSH command disappears.
        ${lib.getExe' pkgs.util-linux "flock"} --nonblock --conflict-exit-code 75 ${lockRoot}/${slot}.request.lock \
          ${lib.getExe' pkgs.systemd "systemd-run"} --system --wait --pipe --quiet --collect \
          --service-type=exec --expand-environment=no \
          ${lib.escapeShellArgs (lib.mapAttrsToList (name: value: "--property=${name}=${toString value}") remoteProperties)} \
          -- ${slotctl} "$@"
        status=$?
        if [[ $status == 75 ]]; then
          printf '%s\n' slot-busy >&2
          exit 1
        fi
        exit "$status"
      '';
    in {
      inherit spec slotDirs prepareDirs slotctlEntry sandbox remoteProperties remoteAction dependencies vm controlDir trustDir;
      inherit (class) runnerMinutes;
      users.groups.${slotUser} = {};
      users.users.${slotUser} = {
        isSystemUser = true;
        group = slotUser;
        # No kvm group: /dev/kvm, /dev/vhost-net and /dev/net/tun are 0666 on
        # Ryza. Without it the slot can't write the microvm:kvm 0775 state
        # dir or the persistent guests' dirs, even outside its sandbox.
      };
      # Keep the upstream GC link, but the installer creates the directories:
      # tmpfiles refuses the owner transition from the microvm-owned parent.
      systemd.tmpfiles.settings."10-microvm".${controlDir} = lib.mkForce {};
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
      # The guest's vCPUs, and its memory plus one GiB for QEMU and virtiofsd.
      systemd.slices.${sliceName}.sliceConfig = {
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
            RuntimeMaxSec = "${toString class.hostMinutes}min";
            TimeoutStartSec = "${toString vmStartSeconds}s";
            TimeoutStopSec = "${toString vmStopSeconds}s";
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
    slotctlSlots = lib.mapAttrs (_: data: data.slotctlEntry) localSlots;
    slotctlConfig = pkgs.writeText "${hostName}-slotctl.json" (builtins.toJSON {slots = slotctlSlots;});
    # Both entry points use the same source with host paths baked in. The
    # caller can choose a declared slot and verb, never the config or systemctl.
    slotctlScript = pkgs.replaceVars ./_forgejo-slotctl.py {
      config = slotctlConfig;
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      systemd_run = lib.getExe' pkgs.systemd "systemd-run";
      python = lib.getExe pkgs.python3;
    };
    slotctl = pkgs.writeShellScript "forgejo-slotctl" ''
      exec ${lib.getExe pkgs.python3} -I -B ${slotctlScript} "$@"
    '';
    forcedCommand = pkgs.writeShellScript "forgejo-slotctl-forced-command" ''
      exec ${lib.getExe pkgs.python3} -I -B -c ${lib.escapeShellArg ''
        from runpy import run_path
        scope = run_path(${builtins.toJSON "${slotctlScript}"})
        raise SystemExit(scope["forced_main"](
            launchers=${builtins.toJSON (lib.mapAttrs (_: data: "${data.remoteAction}") localSlots)},
        ))
      ''}
    '';
    # A single ed25519 key per file; don't copy comments or arbitrary lines
    # into either the server's authorized_keys or the client's known_hosts.
    readEd25519 = path: let
      match = builtins.match "(ssh-ed25519 [A-Za-z0-9+/]+={0,2})( [^[:cntrl:]]*)?" (lib.trim (builtins.readFile path));
    in
      if match != null
      then builtins.head match
      else throw "forgejoEphemeral: expected one ed25519 public key in ${toString path}.";
    sshClient = machine: let
      address = self.lib.hosts.${machine};
      hostKey = readEd25519 (self.lib.vars.machine machine "openssh" "ssh.id_ed25519.pub");
      knownHosts = pkgs.writeText "${machine}-slotctl-known-hosts" "${address} ${hostKey}\n";
      sshConfig = pkgs.writeText "${machine}-slotctl-ssh-config" ''
        Host slot-host
          HostName ${address}
          User root
          BindAddress ${self.lib.hosts.${hostName}}
          BatchMode yes
          PreferredAuthentications publickey
          IdentitiesOnly yes
          IdentityAgent none
          ForwardAgent no
          ClearAllForwardings yes
          StrictHostKeyChecking yes
          HostKeyAlgorithms ssh-ed25519
          UserKnownHostsFile ${knownHosts}
          GlobalKnownHostsFile none
          UpdateHostKeys no
          ControlMaster auto
          ControlPersist 60
          ConnectTimeout 5
          ServerAliveInterval 10
          ServerAliveCountMax 2
      '';
    in
      pkgs.writeShellScript "${machine}-slotctl-ssh" ''
        set -eu
        exec ${lib.getExe' pkgs.openssh "ssh"} -T -F ${sshConfig} \
          -i "$CREDENTIALS_DIRECTORY/slotctl-ssh-key" -S "$RUNTIME_DIRECTORY/s" \
          slot-host -- "$1"
      '';
    sshClients = lib.genAttrs (lib.unique (builtins.filter (machine: machine != hostName) (builtins.attrValues serves))) sshClient;
    # Keep the live Ryza pilot's state and pause marker through the upgrade.
    legacyDispatcher = slot: machine: hostName == "ryza" && machine == "ryza" && slot == "ryza-eph-1";
    stateName = slot: machine:
      if legacyDispatcher slot machine
      then dispatch
      else "${dispatch}-${slot}";
    runtimeName = slot: machine:
      if legacyDispatcher slot machine
      then dispatch
      else "forgejo-ephemeral-${slot}";
    stateDirs = lib.mapAttrs (slot: machine: "/var/lib/${stateName slot machine}") serves;
    claimStates = pkgs.writeText "${hostName}-forgejo-ephemeral-claim-states.json" (builtins.toJSON stateDirs);
    mkDispatcher = slot: machine: let
      local = machine == hostName;
      data = localSlots.${slot};
      class = classFor inventory.${machine}.slots.${slot};
      vmDeadline = vmStartSeconds + class.hostMinutes * 60 + vmStopSeconds;
      state = stateName slot machine;
      runtime = runtimeName slot machine;
      deps = lib.optionals local data.dependencies;
      transport =
        if local
        then "--slotctl ${slotctl}"
        else "--ssh-command ${sshClients.${machine}}";
    in {
      overrideStrategy = "asDropin";
      wantedBy = ["multi-user.target"];
      requires = deps;
      after = deps;
      serviceConfig =
        (
          if local
          then data.sandbox
          else {
            InaccessiblePaths = inaccessibleVMs null;
            CapabilityBoundingSet = "";
          }
        )
        // {
          ExecStart = lib.concatStringsSep " " ([
              (lib.getExe pkgs.python3)
              "-I -B ${./_forgejo-ephemeral-dispatcher.py}"
              "--slot ${slot} --machine ${machine} ${transport}"
              "--pools ${poolsFile}"
              "--state-dir ${stateDirs.${slot}} --pause-file /run/${runtime}/pause"
              "--host-pause-file ${runRoot}/pause --claim-states ${claimStates}"
              "--vm-deadline ${toString vmDeadline}"
            ]
            ++ lib.optional cfg.trustedJobs.enable "--trusted-jobs");
          LoadCredential = lib.optional (!local) "slotctl-ssh-key:${config.clan.core.vars.generators.${sshGenerator}.files.id_ed25519.path}";
          StateDirectory = state;
          RuntimeDirectory = runtime;
        };
    };
    slotDefinitions = f: lib.mkMerge (lib.mapAttrsToList (_: f) localSlots);
    indexes = lib.mapAttrsToList (_: data: data.spec.index) localSlots;
  in {
    imports = [
      # A path module, so importing it here as well as in
      # forgejo-runner-microvm.nix loads it once.
      self.inputs.microvm.nixosModules.host
      self.nixosModules.ci-credentials
      (import ./_forgejo-ephemeral-trusted.nix {inherit cfg localSlots dispatch dispatching cacheHost;})
    ];

    options.services.imperium.forgejoEphemeral = {
      enable = lib.mkEnableOption "the Forgejo one-job slots hosted or dispatched by this machine";
      inventory = lib.mkOption {
        type = lib.types.attrs;
        default = self.lib.ciSlots;
        defaultText = lib.literalExpression "self.lib.ciSlots";
        description = "Shared slot inventory (modules/rites/_ci-slots.nix). A host's dispatcher defaults to itself.";
      };
      dispatcherPublicKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if remoteServer
          then self.lib.vars.machine sourceDispatcher sshGenerator "id_ed25519.pub"
          else null;
        description = "Public slotctl key of the assigned dispatcher, used only on a remote slot host.";
      };
      trustedJobs.enable = lib.mkEnableOption ''
        delivering the CI signing key and ncps upload netrc to jobs whose exact run matches
        the pool's trust allowlist and default-branch policy. The PAT then also needs read:repository
        and, for organization team member lookups, read:organization (included in write:organization).
        For remote slots enable on both sides. See _forgejo-ephemeral-trusted.nix'';
      pools = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            forge = mkOption {
              type = types.enum (builtins.attrNames forgeHosts);
              description = "Forgejo instance hosting this queue.";
            };
            scope = mkOption {
              type = types.attrsOf forgejoLogin;
              description = ''
                Exactly one queue owner: { user = "login"; } or { org = "organization"; }.
                The forge's PAT needs write:user and must belong to the user pool's account,
                or to manjo if the forge only has org pools. Listing jobs and listing,
                registering, and deleting org runners also require that the PAT belongs to
                an organization owner and has write:organization.
              '';
            };
            labels = mkOption {
              type = types.listOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]{0,63}");
              description = "Accepted runs-on labels. A job must request exactly one of these.";
            };
            dispatch = mkOption {
              type = types.either (types.enum ["owner"]) (types.nonEmptyListOf types.ints.positive);
              description = ''Repositories to dispatch: "owner" for the whole scope, or a list of numeric repo IDs.'';
            };
            maxSlots = mkOption {
              type = types.ints.positive;
              default = lib.max 1 (lib.length dispatcherNames);
              description = "Maximum simultaneous slot claims for this pool. Defaults to the number of slots served.";
            };
            trust.repos = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  owner = mkOption {
                    type = forgejoLogin;
                    description = "Expected repository owner (must match the pool's scope).";
                  };
                  name = mkOption {
                    type = forgejoRepoName;
                    description = "Expected repository name.";
                  };
                  schedules = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Trust this repository's scheduled runs. Forgejo re-creates every schedule
                      on any default-branch push and runs it as forgejo-actions, so this trusts
                      whoever last wrote the default branch, not trust.users. Enable only where
                      the trust.repos precondition holds and a schedule needs the cache.
                    '';
                  };
                };
              });
              default = {};
              description = ''
                Repositories eligible for trusted jobs, keyed by numeric repo ID. List a repository
                only if nobody outside trust.users can write its default branch: the personal repo
                owner, write/admin collaborators, and all members of every team with access on an
                org repo must be in trust.users. Require an exact-name branch protection rule for the
                default branch whose push and merge allowlists are subsets of trust.users with no
                teams and no unprotected file patterns, no write deploy key, and not a pull mirror.
                The dispatcher checks these conditions for every resolution. trust.users filters who
                triggers a run, never who wrote the code it runs (see _forgejo-ephemeral-trusted.nix).
              '';
            };
            trust.users = mkOption {
              type = types.listOf forgejoLogin;
              default = [];
              description = ''
                Users whose pushes or workflow dispatches qualify for trust on allowlisted
                repositories. Required when trust.repos is set. Logins are pinned to their account
                IDs on startup with trust enabled, so a new account reusing a login is not trusted.
                Removing a login from trust.users prunes its pin on restart.
              '';
            };
          };
        });
        default = {};
        description = "Forgejo queues served by every slot on the dispatcher. Configure only on the dispatcher.";
      };
      egressAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        readOnly = true;
        default =
          if hosted
          then self.lib.lan.${host.egress.untrusted}
          else null;
        description = "Dedicated SNAT source of this host's slots. The host's uplink must carry it as a /32.";
      };
      internal = lib.mkOption {
        internal = true;
        readOnly = true;
        type = lib.types.attrs;
        default = {
          slots =
            lib.mapAttrs (_: data: {
              inherit (data) slotDirs prepareDirs runnerMinutes;
              inherit pickupSeconds;
            })
            localSlots;
          remotePropertyNames = lib.mapAttrs (_: data: builtins.attrNames data.remoteProperties) localSlots;
          inherit slotctlSlots sshClients poolsFile;
        };
        description = "Slot, pool, and transport details for checks.";
      };
    };

    config = lib.mkMerge [
      # Override the upstream option default (true), but not another host
      # module's mkDefault opt-in, such as the persistent Forgejo runner.
      {microvm.host.enable = lib.mkOverride 1100 false;}
      (lib.mkIf cfg.enable {
        assertions =
          [
            {
              assertion = hosted || dispatching;
              message = "forgejoEphemeral: ${hostName} must host or dispatch a slot in the inventory.";
            }
            {
              assertion = dispatching == (cfg.pools != {});
              message = "forgejoEphemeral: dispatchers must configure at least one pool; slot-only hosts must not configure pools.";
            }
            {
              assertion = allUnique (map (pool: [pool.forge (lib.mapAttrs (_: lib.toLower) pool.scope)]) pools);
              message = "forgejoEphemeral: pool queue identities (forge, scope kind, and case-insensitive owner) must be unique.";
            }
            {
              assertion = allUnique (map (pool: pool.forge) userPools);
              message = "forgejoEphemeral: a forge can have at most one user scope because it uses one PAT.";
            }
            {
              assertion = lib.length (lib.unique (lib.mapAttrsToList dispatcherFor inventory)) <= 1;
              message = "forgejoEphemeral: every inventory entry must use the same dispatcher machine.";
            }
            {
              assertion =
                lib.all (slot: builtins.match "[a-z][a-z0-9-]{0,62}" slot != null && slot != "ryza" && !lib.hasSuffix "-trust" slot) allSlotNames
                && lib.length (lib.unique allSlotNames) == lib.length allSlotNames;
              message = "forgejoEphemeral: slot names must be unique, match [a-z][a-z0-9-]{0,62}, and not be ryza or end in -trust.";
            }
            {
              assertion =
                lib.all (index: index >= 1 && index <= 253) indexes
                && lib.length (lib.unique indexes) == lib.length indexes;
              message = "forgejoEphemeral: slot indexes on ${hostName} must be unique and between 1 and 253.";
            }
          ]
          ++ lib.optionals dispatching poolAssertions;
        systemd.tmpfiles.rules = lib.optional dispatching "d ${runRoot} 0700 root root - -";
      })
      (lib.mkIf (cfg.enable && hosted) {
        assertions = [
          {
            assertion = config.networking.firewall.enable && !config.networking.nftables.enable;
            message = "forgejoEphemeral needs the iptables firewall (networking.firewall without nftables).";
          }
          {
            # The label rule (forgejo-runner.nix) requires a compatible toolset.
            assertion = lib.all (p: builtins.elem p (slotToolset pkgs)) (ciToolset pkgs);
            message = "forgejoEphemeral: the slot's PATH must carry the whole shared CI toolset (_ci-toolset.nix).";
          }
        ];
        users = slotDefinitions (data: data.users);
        microvm.vms = slotDefinitions (data: data.microvm.vms);
        systemd.network.networks = slotDefinitions (data: data.systemd.network.networks);
        systemd.slices = slotDefinitions (data: data.systemd.slices);
        systemd.services = slotDefinitions (data: data.systemd.services);
        systemd.tmpfiles.settings."10-microvm" = slotDefinitions (data: data.systemd.tmpfiles.settings."10-microvm");
        systemd.tmpfiles.rules =
          [
            # The installer also creates this root-owned parent.
            "d ${credParent} 0755 root root - -"
            "d ${lockRoot} 0700 root root - -"
          ]
          ++ lib.concatMap (slot: let
            credentials = slotCredentials slot;
          in
            ["f ${lockRoot}/${slot}.lock 0600 root root - -"]
            # An optional inaccessible path would be skipped if its peer's
            # installer had not run yet when this namespace was created.
            ++ lib.optional (credentials != credParent) "d ${credentials} 0755 root root - -")
          (builtins.attrNames localSlots);
        # The guard owns forwarding and SNAT; don't add its TAP to stock NAT.
        boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = lib.mkDefault true;
        microvm.host.enable = true;
      })
      (lib.mkIf (cfg.enable && dispatching) {
        clan.core.vars.generators = lib.mapAttrs' (forge: {
          login,
          hasOrg,
          generator,
          ...
        }: let
          scopes =
            ["write:user"]
            ++ lib.optional hasOrg "write:organization"
            ++ lib.optional cfg.trustedJobs.enable "read:repository";
          # Public only rejects non-public orgs on the org routes; user queues work with it.
          publicOnly = lib.optionalString (!hasOrg) "Public only; ";
          scopesText = lib.concatStringsSep " and " scopes + lib.optionalString (scopes == ["write:user"]) " only";
        in
          lib.nameValuePair generator {
            share = false;
            prompts.token = {
              description = "Forgejo dispatcher PAT for ${login} on ${forgeHosts.${forge}} (${publicOnly}${scopesText})";
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
          })
        forgeSettings;
        # Only hosts with an ephemeral root (ryza) have this option.
        services = lib.optionalAttrs (options.services.imperium ? impermanence) {
          imperium.impermanence.directories = map (directory: {
            inherit directory;
            user = "root";
            group = "root";
            mode = "0700";
          }) (builtins.attrValues stateDirs);
        };
        systemd.tmpfiles.rules = ["d ${claims} 0700 root root - -"];
        systemd.services =
          {
            "${dispatch}@" = {
              description = "Dispatch Forgejo jobs to slot %i";
              # NixOS links wantedBy to the instance filename; an asDropin
              # definition only creates the .d directory, so link the filename
              # itself to the real template as systemctl enable would.
              aliases = map (name: "${name}.service") dispatcherNames;
              wants = ["network-online.target"];
              after = ["network-online.target" "systemd-tmpfiles-setup.service"];
              serviceConfig =
                commonSandbox
                // {
                  Type = "exec";
                  LoadCredential = lib.mapAttrsToList (_: {
                    credential,
                    generator,
                    ...
                  }: "${credential}:${config.clan.core.vars.generators.${generator}.files.token.path}")
                  forgeSettings;
                  StateDirectoryMode = "0700";
                  RuntimeDirectoryMode = "0700";
                  RuntimeDirectoryPreserve = "yes";
                  ReadWritePaths = [claims];
                  RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
                  Restart = "on-failure";
                  RestartSec = "7s";
                };
            };
          }
          // lib.mapAttrs' (slot: machine: lib.nameValuePair "${dispatch}@${slot}" (mkDispatcher slot machine)) serves;
      })
      (lib.mkIf (cfg.enable && remoteClient) {
        clan.core.vars.generators.${sshGenerator} = {
          share = false;
          files.id_ed25519 = {
            secret = true;
            owner = "root";
            group = "root";
            mode = "0400";
          };
          files."id_ed25519.pub".secret = false;
          runtimeInputs = [pkgs.openssh];
          script = ''
            ssh-keygen -q -t ed25519 -N "" -C "forgejo-slotctl@${hostName}" -f "$out/id_ed25519"
          '';
        };
      })
      (lib.mkIf (cfg.enable && remoteServer) {
        assertions = [
          {
            assertion = builtins.hasAttr sourceDispatcher self.lib.hosts;
            message = "forgejoEphemeral: give ${sourceDispatcher} a source IP in the network chart.";
          }
          {
            assertion = config.services.openssh.enable && config.services.openssh.settings.PermitRootLogin != "no";
            message = "forgejoEphemeral: remote slotctl requires an existing SSH policy permitting forced root keys.";
          }
        ];
        users.users.root.openssh.authorizedKeys.keys = [
          ''command="${forcedCommand}",restrict,from="${self.lib.hosts.${sourceDispatcher}}" ${readEd25519 cfg.dispatcherPublicKeyFile}''
        ];
      })
    ];
  };
}
