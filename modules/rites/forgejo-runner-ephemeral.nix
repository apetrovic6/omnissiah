{self, ...}: {
  flake.nixosModules.forgejo-runner-ephemeral = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.imperium.forgejoEphemeral;
    generator = "forgejo-ephemeral-ugalabugala";
    dispatch = "forgejo-ephemeral-dispatcher";
    forgeHost = "forge.${self.lib.lab.domain}";
    cacheHost = "ncps.noosphere.uk";
    slotUser = "microvm-eph";
    slot = "ryza-eph-1";
    slice = "forgejo-ephemeral.slice";
    vm = "microvm@${slot}";
    # Root-only writes to current/booted and the virtiofsd working directory.
    # QEMU owns only its runtime data, never the parent used by root hooks.
    controlDir = "${config.microvm.stateDir}/${slot}";
    vmDir = "${controlDir}/job";
    credParent = "/run/microvm-credentials";
    credDir = "${credParent}/${slot}";
    credIds = ["runner-token" "runner-uuid" "job-handle"];
    overlay = "/nix/.rw-store";
    images = ["nix-store-overlay.img" "var.img"];
    tap = "vm-eph-1";
    uplink = "ens18";
    mac = "02:00:00:c1:00:03";
    gateway = "10.99.2.1";
    address = "10.99.2.2";
    inherit (self.lib.hosts) cerberus;
    inherit (self.lib.lan) ryza-eph;
    persistentPaths =
      ["-/persist"]
      ++ lib.concatMap
      (name: ["-${credParent}/${name}" "-${config.microvm.stateDir}/${name}"])
      ["ryza-ci-noosphere" "ryza-ci-ugalabugala" "ryza-ci"];
    guard = "forgejo-ephemeral-firewall";
    outChain = "ryza-eph-out";
    inChain = "ryza-eph-in";
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
      -A ${outChain} -d ${cerberus} -p udp --dport 53 -j RETURN
      -A ${outChain} -d ${cerberus} -p tcp --dport 53 -j RETURN
      -A ${outChain} -d ${cerberus} -p tcp --dport 443 -j RETURN
      ${lib.concatMapStringsSep "\n" (net: "-A ${outChain} -d ${net} -j DROP") nonPublic}
      -A ${outChain} -p tcp --dport 443 -j RETURN
      -A ${outChain} -j DROP
      -A ${inChain} -i ${uplink} -d ${address} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
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
        apply iptables nat 'POSTROUTING -s ${address}/32 -o ${uplink} -j SNAT --to-source ${ryza-eph}'
        apply ip6tables filter 'INPUT -i ${tap} -j DROP' 'OUTPUT -o ${tap} -j DROP' \
          'FORWARD -i ${tap} -j DROP' 'FORWARD -o ${tap} -j DROP'
        apply iptables filter 'INPUT -i ${tap} -j DROP' 'OUTPUT -o ${tap} -j DROP' \
          'FORWARD -i ${tap} -j ${outChain}' 'FORWARD -o ${tap} -j ${inChain}'
      }
    '';
    preflight = pkgs.writeShellScript "${slot}-preflight" ''
      set -eu
      for file in ${lib.escapeShellArgs (map (id: "${credDir}/${id}") credIds)}; do
        [[ -f "$file" && ! -L "$file" && -r "$file" && -s "$file" ]]
      done
      for file in ${lib.escapeShellArgs images}; do
        [[ ! -e "$file" && ! -L "$file" ]]
      done
    '';
    scrub = pkgs.writeShellScript "${slot}-scrub" ''
      set -eu
      ${lib.getExe' pkgs.coreutils "rm"} -f -- ${lib.escapeShellArgs (map (image: "${vmDir}/${image}") images)}
      if [[ -d ${credDir} && ! -L ${credDir} ]]; then
        ${lib.getExe' pkgs.coreutils "rm"} -f -- ${lib.escapeShellArgs (map (id: "${credDir}/${id}") credIds)}
        ${lib.getExe' pkgs.coreutils "rmdir"} -- ${credDir}
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
            CARGO_BUILD_JOBS = "2";
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
        vcpu = 2;
        mem = 4096;
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
            size = 50 * 1024;
          }
          {
            image = builtins.elemAt images 1;
            mountPoint = "/var";
            size = 20 * 1024;
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
        cores = 2;
        min-free = 10 * 1024 * 1024 * 1024;
        max-free = 25 * 1024 * 1024 * 1024;
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
        path =
          [config.nix.package]
          ++ (with pkgs; [
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
          ]);
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
            --label nix-eph:host --handle "$handle" --wait
        '';
      };
    };
  in {
    options.services.imperium.forgejoEphemeral = {
      enable = lib.mkEnableOption "the Ryza Forgejo one-job microVM pilot";
      repoId = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Numeric Forgejo repository ID of manjo/rust-app-template, the only eligible repository.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.repoId != null;
          message = "forgejoEphemeral: set the numeric ID of manjo/rust-app-template.";
        }
        {
          assertion =
            config.networking.hostName
            == "ryza"
            && config.microvm.host.enable
            && config.networking.firewall.enable
            && !config.networking.nftables.enable
            && config.networking.nat.externalInterface == uplink;
          message = "forgejoEphemeral requires Ryza's microVM host and iptables NAT via ens18.";
        }
      ];
      clan.core.vars.generators.${generator} = {
        share = false;
        prompts.token = {
          description = "Forgejo dispatcher PAT for manjo on forge.ugalabugala.org (Public only; write:user only)";
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
      services.imperium.impermanence.directories = [
        {
          directory = "/var/lib/${dispatch}";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
      systemd.tmpfiles.rules = ["d ${credParent} 0755 root root - -"];
      users.groups.${slotUser} = {};
      users.users.${slotUser} = {
        isSystemUser = true;
        group = slotUser;
        extraGroups = ["kvm"];
      };
      systemd.tmpfiles.settings."10-microvm" = {
        ${controlDir}.d = {
          user = lib.mkForce "root";
          group = lib.mkForce slotUser;
          mode = lib.mkForce "0750";
        };
        ${vmDir}.d = {
          user = slotUser;
          group = slotUser;
          mode = "0700";
        };
      };
      microvm.vms.${slot} = {
        autostart = false;
        restartIfChanged = false;
        config = {
          imports = [guest];
          system.stateVersion = config.system.stateVersion;
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
      networking.nat.internalInterfaces = [tap];
      systemd.slices.forgejo-ephemeral.sliceConfig = {
        CPUQuota = "200%";
        MemoryMax = "5G";
        MemorySwapMax = 0;
        IOWeight = 20;
      };
      systemd.services = {
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
          requires = ["install-microvm-${slot}.service" "${guard}.service"];
          after = ["network-online.target" "install-microvm-${slot}.service" "${guard}.service"];
          path = [pkgs.systemd];
          serviceConfig = {
            Type = "exec";
            ExecStart = "${lib.getExe pkgs.python3} -I -B ${./_forgejo-ephemeral-dispatcher.py} --repo-id ${toString cfg.repoId} --state-dir /var/lib/${dispatch} --vm-dir ${vmDir} --credential-dir ${credDir}";
            LoadCredential = ["forgejo-pat:${config.clan.core.vars.generators.${generator}.files.token.path}"];
            StateDirectory = dispatch;
            StateDirectoryMode = "0700";
            RuntimeDirectory = dispatch;
            RuntimeDirectoryMode = "0700";
            RuntimeDirectoryPreserve = "yes";
            ProtectSystem = "strict";
            ReadWritePaths = [credParent "-${vmDir}"];
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
          bindsTo = ["${guard}.service"];
          after = ["${guard}.service"];
          serviceConfig = {
            Slice = slice;
            User = slotUser;
            Group = slotUser;
            WorkingDirectory = vmDir;
            ProtectSystem = "strict";
            ReadWritePaths = [vmDir "-${credDir}"];
            ProtectHome = true;
            PrivateTmp = true;
            InaccessiblePaths = persistentPaths;
            NoNewPrivileges = true;
            Restart = "no";
            RuntimeMaxSec = "75min";
            TimeoutStartSec = "90s";
            TimeoutStopSec = "30s";
            ExecStartPre = [preflight];
            ExecStopPost = ["+${scrub}"];
            LimitCORE = 0;
          };
        };
        "microvm-set-booted@${slot}" = {
          overrideStrategy = "asDropin";
          serviceConfig = {
            User = "root";
            Group = "root";
          };
        };
        "microvm-virtiofsd@${slot}".serviceConfig.Slice = slice;
      };
    };
  };
}
