# With `isolation = "microvm"`, each forge's jobs run in a dedicated qemu
# guest. Jobs cannot see the other forge's token or the host's files,
# processes and secrets. Ryza also runs the agent and its subscription logins.
# Both QEMUs run as `microvm`; this isolates guest root and the guest kernel,
# not a QEMU escape.
#
#   identity   unchanged and on the host: the clan vars, `nix run
#              .#forgejo-runner-register -- <machine>`, the runner name
#   runtime    the same runtimeConfig as the host runner, with one connection
#   secrets    only that forge's token plus the shared CI signing key, ncps
#              netrc and sccache key. A root unit stages them for qemu (which
#              runs as `microvm`); the guest gets them as systemd credentials
#              under /run/credentials/@system
#   store      the host's /nix/store read-only over virtiofs, plus a writable
#              overlay on its own disk image for what the jobs build
#   network    a tap with a /24 of its own, NATed out through the host's
#              uplink: forges, ncps, Harbor, Garage, the internet
#   size       `resources` is the combined budget, divided among guests
#
# The guest's Nix database is on its tmpfs root, so after a VM restart the
# overlay's paths are unregistered again: Nix re-fetches what it needs from
# ncps, which every runner pushes to, and collects the rest.
#
# Inspect a guest: `journalctl -u microvm@<machine>-ci-<forge>` (console).
{self, ...}: {
  flake.nixosModules.forgejo-runner-microvm = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption types;
    cfg = config.services.imperium.forgejoRunner;
    m = cfg.microvm;
    active = cfg.enable && cfg.isolation == "microvm";
    legacyVM = "${config.networking.hostName}-ci";
    legacyUnit = "microvm@${legacyVM}.service";
    # Stable even when a machine enables just one forge. No overlap with
    # Podman's 10.88 or RKE2's 10.42/10.43.
    links = {
      noosphere = {
        tap = "vm-ci-noo";
        subnet = "10.99.0";
        mac = "02:00:00:c1:00:01";
      };
      ugalabugala = {
        tap = "vm-ci-uga";
        subnet = "10.99.1";
        mac = "02:00:00:c1:00:02";
      };
    };
    forgeNames = builtins.attrNames cfg.guests;
    guestCount = builtins.length forgeNames;
    resourcesFit = cfg.resources != null && cfg.resources.cpus >= guestCount && cfg.resources.memory >= guestCount;
    share = total: index: let
      base = total / guestCount;
      remainder = total - base * guestCount;
    in
      base
      + (
        if index < remainder
        then 1
        else 0
      );
    guests = lib.imap0 (index: forge:
      links.${forge}
      // {
        inherit forge index;
        inherit (cfg.guests.${forge}) module credentialSources;
        vmName = "${config.networking.hostName}-ci-${forge}";
      })
    forgeNames;
    taps = map (guest: guest.tap) guests;

    guestServices = {
      vmName,
      credentialSources,
      ...
    }: let
      vmUnit = "microvm@${vmName}.service";
      credDir = "/run/microvm-credentials/${vmName}";
    in {
      # The legacy instance could still be running through microvm@.service.
      # Stop it before the new guests start polling with the same identities.
      "microvm@${vmName}" = {
        conflicts = [legacyUnit];
        after = [legacyUnit];
      };
      "microvm-credentials-${vmName}" = {
        description = "Stage the CI microVM's credentials for qemu";
        before = [vmUnit];
        requiredBy = [vmUnit];
        partOf = [vmUnit];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "microvm-credentials/${vmName}";
          RuntimeDirectoryMode = "0700";
        };
        script = ''
          install -d -m 0700 -o microvm -g kvm ${credDir}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (id: src: ''
              install -m 0400 -o microvm -g kvm ${lib.escapeShellArg src} ${credDir}/${id}
            '')
            credentialSources)}
        '';
        path = [pkgs.coreutils];
      };
    };

    guestVM = {
      forge,
      index,
      vmName,
      tap,
      subnet,
      mac,
      module,
      credentialSources,
    }:
      lib.nameValuePair vmName {
        autostart = true;
        config = {
          imports = [module];

          networking.hostName = vmName;
          system.stateVersion = config.system.stateVersion;

          microvm = {
            hypervisor = "qemu";
            vcpu = share cfg.resources.cpus index;
            mem = share cfg.resources.memory index * 1024;

            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
                readOnly = true;
              }
            ];
            writableStoreOverlay = "/nix/.rw-store";

            # Image files live in /var/lib/microvms/<vm>/ on the host.
            volumes = [
              {
                image = "nix-store-overlay.img";
                mountPoint = "/nix/.rw-store";
                size = m.storeOverlay * 1024;
              }
              {
                image = "var.img";
                mountPoint = "/var";
                size = m.var * 1024;
              }
            ];

            interfaces = [
              {
                type = "tap";
                id = tap;
                inherit mac;
              }
            ];

            credentialFiles = lib.mapAttrs (id: _: "/run/microvm-credentials/${vmName}/${id}") credentialSources;

            # qemu takes host RAM as the guest first touches it and, without
            # this, never gives any back: after one big build the VM held
            # all 14 GiB on ryza for good (2026-11-22). The balloon device
            # brings free page reporting, so pages the guest frees go back
            # to the host; deflate-on-oom (the default) returns them if the
            # guest runs short. `mem` stays the hard cap.
            balloon = true;
          };

          # Free page reporting only returns FREE pages, and Linux keeps
          # spare RAM full of page cache (store paths, cargo output), which
          # counts as used. So when no job is running, drop the cache and
          # compact, and the freed pages flow back to the host. Busy = any
          # process in the runner's or nix-daemon's cgroup besides the main
          # one: a job's steps, or a build.
          systemd.services.ci-release-memory = {
            description = "Return idle page cache to the host";
            serviceConfig.Type = "oneshot";
            script = let
              procs = unit: "/sys/fs/cgroup/system.slice/${unit}/cgroup.procs";
            in ''
              busy() { [ -r "$1" ] && [ "$(wc -l < "$1")" -gt 1 ]; }
              if busy ${procs "forgejo-runner-${forge}.service"} \
                || busy ${procs "nix-daemon.service"}; then
                exit 0
              fi
              sync
              echo 3 > /proc/sys/vm/drop_caches
              echo 1 > /proc/sys/vm/compact_memory
            '';
          };
          systemd.timers.ci-release-memory = {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnBootSec = "10min";
              OnUnitActiveSec = "5min";
            };
          };

          networking.useNetworkd = true;
          networking.useDHCP = false;
          systemd.network.networks."10-uplink" = {
            matchConfig.MACAddress = mac;
            address = ["${subnet}.2/24"];
            gateway = ["${subnet}.1"];
            # The LAN's Blocky resolvers: ncps.noosphere.uk and the forges
            # must resolve to the LAN, as on every other runner.
            dns = self.lib.lan.resolvers;
          };

          nix.settings = let
            gib = n: n * 1024 * 1024 * 1024;
          in {
            experimental-features = ["nix-command" "flakes"];
            # Sandbox build scratch belongs on the /var disk, not the root tmpfs.
            build-dir = "/var/nix-builds";
            # As stc/base.nix sets on every clan machine; the guest is not
            # one, so it does not get that module.
            substituters = ["https://ncps.noosphere.uk"];
            trusted-public-keys = [
              (builtins.readFile (self.lib.vars.shared "ncps-signing-key" "ncps-signing-key.pub"))
            ];
            min-free = gib (m.storeOverlay / 5);
            max-free = gib (m.storeOverlay / 2);
          };
        };
      };
  in {
    imports = [
      self.inputs.microvm.nixosModules.host
      self.nixosModules.forgejo-runner
    ];

    options.services.imperium.forgejoRunner.microvm = {
      uplink = mkOption {
        type = types.str;
        example = "ens18";
        description = "The host interface the guests' traffic is NATed out through.";
      };
      storeOverlay = mkOption {
        type = types.ints.positive;
        default = 50;
        description = "GiB per guest's writable /nix/store overlay. The guest collects garbage below a fifth of it free.";
      };
      var = mkOption {
        type = types.ints.positive;
        default = 20;
        description = "GiB per guest's /var: Nix build scratch, runner state, workspaces, TMPDIR and CARGO_HOME.";
      };
    };

    config = lib.mkMerge [
      {microvm.host.enable = lib.mkDefault active;}

      (mkIf active {
        assertions = [
          {
            assertion = resourcesFit;
            message = "forgejoRunner: microVM resources must provide at least one vCPU and one GiB per guest.";
          }
        ];
        # This exact path has no forge suffix. Never remove the sibling
        # RuntimeDirectory trees used by the new guests.
        systemd.tmpfiles.rules = ["R /run/microvm-credentials/${legacyVM} - - - - -"];
      })

      (mkIf (active && resourcesFit) {
        systemd.services = lib.mkMerge (map guestServices guests);
        microvm.vms = builtins.listToAttrs (map guestVM guests);

        # Host side of each point-to-point link, and NAT out the uplink.
        systemd.network.networks = builtins.listToAttrs (map ({
          tap,
          subnet,
          ...
        }:
          lib.nameValuePair "20-${tap}" {
            matchConfig.Name = tap;
            address = ["${subnet}.1/24"];
            networkConfig.ConfigureWithoutCarrier = true;
            linkConfig.RequiredForOnline = "no";
          })
        guests);
        networking.nat = {
          enable = true;
          internalInterfaces = taps;
          externalInterface = m.uplink;
          # NAT adds uplink accepts, but does not drop inter-guest traffic.
          extraCommands = mkIf (!config.networking.nftables.enable) (lib.concatMapStringsSep "\n" (tap:
            lib.concatMapStringsSep "\n" (other: ''
              iptables -w -I nixos-filter-forward -i ${tap} -o ${other} -j DROP
            '') (builtins.filter (other: other != tap) taps))
          taps);
        };
        networking.nftables.tables.forgejo-ci = mkIf (config.networking.nftables.enable && guestCount > 1) {
          family = "inet";
          content = let
            interfaces = lib.concatMapStringsSep ", " builtins.toJSON taps;
          in ''
            chain forward {
              type filter hook forward priority filter; policy accept;
              iifname { ${interfaces} } oifname { ${interfaces} } drop
            }
          '';
        };
      })
    ];
  };
}
