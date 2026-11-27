# What the bare-metal taghmata machines (terra, luna, sol) have in common as
# hosts, apart from their cluster roles (stc/taghmata.nix): the static address
# on the LAN NIC and the CI runner they each carry.
#
# A machine sets only what differs, in machines/<name>/configuration.nix.
{self, ...}: {
  flake.nixosModules.taghmata-node = args @ {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (config.networking) hostName;
    state = (args.ciNodes or self.lib.ciNodes).${hostName};
    runner = config.services.imperium.forgejoRunner;
    slot = config.services.imperium.forgejoEphemeral;
    host = slot.inventory.${hostName};
    inherit (host) uplink;
    inherit (host.egress) interface;
    snatAddresses = builtins.filter (address: address != null) [slot.egressAddress slot.egressTrustedAddress];
    ip = lib.getExe' pkgs.iproute2 "ip";
    arping = lib.getExe' pkgs.iputils "arping";
    uplinkDevice = "sys-subsystem-net-devices-${uplink}.device";
    cleanup = "rke2-clean-dangling-store-links";
  in {
    imports = [
      self.nixosModules.forgejo-runner
      self.nixosModules.sccache
    ];

    # The address is the machine's entry in modules/cartographa/_chart.nix.
    networking.interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = self.lib.hosts.${hostName};
          prefixLength = 24;
        }
      ];
    };
    # Deliberately no addresses on enp1s0 beyond the node's primary /24.
    # Calico first-found excludes ^dummy.*; this device has no default route
    # so k3s's default-route-interface address lookup also excludes it.
    systemd.network.networks = lib.mkIf state.slotsEnabled {
      "10-${interface}" = {
        matchConfig.Name = interface;
        linkConfig.Unmanaged = true;
      };
    };
    systemd.services.forgejo-ephemeral-snat = lib.mkIf state.slotsEnabled {
      description = "Claim the CI SNAT addresses on ${interface}";
      wantedBy = ["multi-user.target"];
      # network-online.target alone does not wait for the uplink here
      # (networkd wait-online off, the NICs NetworkManager-unmanaged).
      wants = ["network-online.target"];
      bindsTo = [uplinkDevice];
      after = ["network-online.target" uplinkDevice];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Boot races (no address yet, ARP probe failing) retry rather than
        # leave the slot refusing every job until a manual restart.
        Restart = "on-failure";
        RestartSec = 10;
        OOMScoreAdjust = 1000;
      };
      script = ''
        set -eu
        for _ in $(seq 60); do
          [[ -n $(${ip} -4 -o address show dev ${uplink} scope global) ]] && break
          sleep 1
        done
        if [[ -z $(${ip} -4 -o address show dev ${uplink} scope global) ]]; then
          echo "CI SNAT: ${uplink} has no IPv4 address after 60 s" >&2
          exit 1
        fi
        # A dummy cannot perform link-layer ACD on the LAN. Probe on the
        # physical interface before binding, and require weak-host ARP.
        for dev in all ${uplink}; do
          for key in arp_ignore arp_filter; do
            if [[ $(<"/proc/sys/net/ipv4/conf/$dev/$key") != 0 ]]; then
              echo "CI SNAT needs $key=0 on $dev to answer LAN ARP for the dummy addresses" >&2
              exit 1
            fi
          done
        done
        for address in ${lib.escapeShellArgs snatAddresses}; do
          if ! ${arping} -q -D -c 2 -w 3 -I ${uplink} "$address"; then
            echo "CI SNAT refused: ARP duplicate-address probe for $address on ${uplink} failed" >&2
            exit 1
          fi
        done
        # Only this unit creates the dummy; drop a leftover of an unclean stop.
        ${ip} link delete ${interface} 2>/dev/null || true
        ${ip} link add ${interface} type dummy
        trap '${ip} link delete ${interface}' EXIT
        ${ip} link set ${interface} up
        for address in ${lib.escapeShellArgs snatAddresses}; do
          ${ip} -4 address add "$address/32" dev ${interface}
        done
        trap - EXIT
      '';
      preStop = ''
        if ${ip} link show dev ${interface} >/dev/null 2>&1; then
          ${ip} link delete ${interface}
        fi
      '';
    };

    # Job images live on the second NVMe (_node-disko.nix), not the root
    # device holding the RKE2 etcd datastore. Never fall back to the root.
    microvm.stateDir = lib.mkIf state.slotsEnabled "/mnt/storage/microvms";
    # mkIf on the whole unit: a nested one would still declare an empty unit.
    systemd.services."install-microvm-${hostName}-eph-1" = lib.mkIf state.slotsEnabled {
      unitConfig.AssertPathIsMountPoint = "/mnt/storage";
    };

    # Tmpfiles installs RKE2's links into the store (nixpkgs
    # services/cluster/rancher) but never removes those of deleted entries.
    # Once the automatic GC is back (from the stage on, taghmata runner
    # storeCache off), it collects their targets, and a single dangling
    # manifest stalls the deploy controller for every bundled chart
    # (README "Large slots on Luna, Sol and Terra"). Only removes links,
    # never touches rke2-server; the controller picks up the next pass.
    systemd.services.${cleanup} = lib.mkIf config.nix.gc.automatic {
      description = "Remove dangling RKE2 links to collected Nix store paths";
      after = ["nix-gc.service"];
      serviceConfig.Type = "oneshot";
      path = [pkgs.findutils];
      script = ''
        set -eu
        rke2=/var/lib/rancher/rke2
        for dir in "$rke2/server/manifests" "$rke2/server/static/charts" "$rke2/agent/images" "$rke2/agent/etc/containerd"; do
          [[ -d "$dir" ]] || continue
          # Print before deleting: %l reads the link.
          find -P "$dir" -xdev -mindepth 1 -type l -lname '/nix/store/*' -xtype l \
            -printf 'Removed dangling RKE2 store link: %p -> %l\n' -delete
        done
      '';
    };
    systemd.timers.${cleanup} = lib.mkIf config.nix.gc.automatic {
      description = "Remove dangling RKE2 store links after any garbage collection";
      wantedBy = ["timers.target"];
      timerConfig = {
        # Also catches manual nix-collect-garbage and min-free collection.
        OnBootSec = "5min";
        OnUnitActiveSec = "15min";
      };
    };
    systemd.services.nix-gc = lib.mkIf config.nix.gc.automatic {
      unitConfig.OnSuccess = ["${cleanup}.service"];
    };
    # No catch-up run when the timer returns at the stage switch: a stamp
    # left from before storeCache (2026-11-03) would start a full GC of
    # weeks of CI store on the etcd root disk right away. The first,
    # chunked GC is the operator's (README step 4).
    nix.gc.persistent = lib.mkIf config.nix.gc.automatic false;
    networking.defaultGateway = {
      address = self.lib.lan.gateway;
      interface = "enp1s0";
    };
    networking.nameservers = self.lib.lan.resolvers;

    # Host-step cargo builds cache into the `sccache` bucket on garage-main
    # (modules/rites/sccache.nix); wired into the runner by forgejo-runner.nix.
    services.imperium.sccache.enable = state.hostRunnerEnabled;

    services.imperium.forgejoRunner = {
      enable = state.hostRunnerEnabled;
      # Both forges: keep general CI and accept the long Machines jobs.
      labels = ["nix:host" "nix-machines:host"];
      # 1.6 TB of free disk: keep CI's store until it gets tight.
      storeCache = lib.mkIf state.hostRunnerEnabled {
        minFree = 200;
        maxFree = 400;
      };
      resources = {
        cpus = lib.mkDefault 2;
        memory = lib.mkDefault 4;
      };
    };

    # Keep the exact flag ordering and reservation set by the host runner
    # even in the intermediate generation without a runner or slot.
    services.rke2.extraFlags = lib.mkIf (!runner.enable && config.services.rke2.enable) (lib.mkAfter [
      "--kubelet-arg=system-reserved=memory=${toString runner.resources.memory}Gi"
    ]);

    users.groups.media = {
      gid = 1337;
    };

    services.dbus.enable = true;
  };
}
