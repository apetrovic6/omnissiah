# The Forgejo runner in a microVM: `services.imperium.forgejoRunner.isolation
# = "microvm"` (modules/rites/forgejo-runner.nix) runs the jobs in a dedicated
# qemu VM on the machine instead of on it, so a job gets its own kernel and
# cannot see the host's files, processes or other secrets. First on ryza,
# which also runs the always-on agent and its subscription logins.
#
#   identity   unchanged and on the host: the clan vars, `nix run
#              .#forgejo-runner-register -- <machine>`, the runner name
#   runtime    the same runtimeConfig the host runner uses, evaluated as the
#              guest's NixOS config (cfg.guestModule), so the toolset matches
#   secrets    only the runner's own: one credential per forge, the CI signing
#              key, the ncps upload netrc, the sccache key. A root unit copies
#              them out of /run/secrets for qemu (which runs as `microvm` and
#              cannot read sops' files) and qemu hands them in as systemd
#              credentials, under /run/credentials/@system in the guest
#   store      the host's /nix/store read-only over virtiofs, plus a writable
#              overlay on its own disk image for what the jobs build
#   network    a tap with a /24 of its own, NATed out through the host's
#              uplink: forges, ncps, Harbor, Garage, the internet
#   size       `resources` is the VM's vCPUs and memory, a hard cap
#
# The guest's Nix database is on its tmpfs root, so after a VM restart the
# overlay's paths are unregistered again: Nix re-fetches what it needs from
# ncps, which every runner pushes to, and collects the rest.
#
# Inspect the guest from the host: `journalctl -u microvm@<machine>-ci`
# (console), `systemctl status microvm@<machine>-ci`.
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
    vmName = "${config.networking.hostName}-ci";
    credDir = "/run/microvm-credentials/${vmName}";
    tap = "vm-ci";
    # Not 10.88 (podman's default) nor 10.42/10.43 (RKE2's pod and service
    # ranges).
    subnet = "10.99.0";
  in {
    imports = [
      self.inputs.microvm.nixosModules.host
      self.nixosModules.forgejo-runner
    ];

    options.services.imperium.forgejoRunner.microvm = {
      uplink = mkOption {
        type = types.str;
        example = "ens18";
        description = "The host interface the VM's traffic is NATed out through.";
      };
      storeOverlay = mkOption {
        type = types.ints.positive;
        default = 100;
        description = "GiB for the guest's writable /nix/store overlay. The guest collects garbage below a fifth of it free.";
      };
      var = mkOption {
        type = types.ints.positive;
        default = 40;
        description = "GiB for the guest's /var: the runner's state, job work dirs and TMPDIR, CARGO_HOME.";
      };
      mac = mkOption {
        type = types.str;
        default = "02:00:00:c1:00:01";
        description = "The guest NIC's MAC (locally administered).";
      };
    };

    config = lib.mkMerge [
      # The host module is imported wherever this file is; only a machine that
      # actually runs a CI VM gets its services.
      {microvm.host.enable = lib.mkDefault active;}

      (mkIf active {
        assertions = [
          {
            assertion = cfg.resources != null;
            message = "forgejoRunner: isolation = \"microvm\" needs `resources`, which sizes the VM.";
          }
        ];

        # Copies of the runner's secrets that qemu, running as `microvm`, can
        # read. In /run, so they never touch the disk, and redone on every VM
        # start so a rotated var is picked up.
        systemd.services."microvm-credentials-${vmName}" = {
          description = "Stage the CI microVM's credentials for qemu";
          before = ["microvm@${vmName}.service"];
          requiredBy = ["microvm@${vmName}.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            install -d -m 0700 -o microvm -g kvm ${credDir}
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (id: src: ''
                install -m 0400 -o microvm -g kvm ${lib.escapeShellArg src} ${credDir}/${id}
              '')
              cfg.credentialSources)}
          '';
          path = [pkgs.coreutils];
        };

        # Host side of the VM's link, and NAT out through the uplink.
        systemd.network.networks."20-${tap}" = {
          matchConfig.Name = tap;
          address = ["${subnet}.1/24"];
          networkConfig.ConfigureWithoutCarrier = true;
          linkConfig.RequiredForOnline = "no";
        };
        networking.nat = {
          enable = true;
          internalInterfaces = [tap];
          externalInterface = m.uplink;
        };

        microvm.vms.${vmName} = {
          autostart = true;
          config = {
            imports = [cfg.guestModule];

            networking.hostName = vmName;
            system.stateVersion = config.system.stateVersion;

            microvm = {
              hypervisor = "qemu";
              vcpu = cfg.resources.cpus;
              mem = cfg.resources.memory * 1024;

              shares = [
                {
                  tag = "ro-store";
                  source = "/nix/store";
                  mountPoint = "/nix/.ro-store";
                  proto = "virtiofs";
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
                  inherit (m) mac;
                }
              ];

              credentialFiles = lib.mapAttrs (id: _: "${credDir}/${id}") cfg.credentialSources;
            };

            networking.useNetworkd = true;
            networking.useDHCP = false;
            systemd.network.networks."10-uplink" = {
              matchConfig.MACAddress = m.mac;
              address = ["${subnet}.2/24"];
              gateway = ["${subnet}.1"];
              # Technitium on cerberus: ncps.noosphere.uk and the forges must
              # resolve to the LAN, as on every other runner.
              dns = [self.lib.lan.dns];
            };

            nix.settings = let
              gib = n: n * 1024 * 1024 * 1024;
            in {
              experimental-features = ["nix-command" "flakes"];
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
      })
    ];
  };
}
