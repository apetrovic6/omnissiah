# The nix-eph slot inventory: which machines run throwaway Forgejo CI VMs, and
# what each slot looks like. Plain data, like the network chart
# (modules/cartographa/_chart.nix), read as `self.lib.ciSlots` by the slot
# module (forgejo-runner-ephemeral.nix), by cerberus's Caddy guard
# (machines/cerberus/proxy.nix) and by the slot hosts' network config, so none
# of them evaluates another machine's configuration.
#
#   guard             machine that slot guests may reach on the LAN: their DNS
#                     resolver and the HTTPS endpoint whose Caddy limits each
#                     slot source to its allowed names
#                     (machines/<guard>/proxy.nix). It also fronts the forge,
#                     ncps, Garage S3, Harbor and ntfy names the guests pin.
#                     Moves with cerberus, separately from the dispatcher.
#
#   uplink            the host interface slot traffic is source-NATed out of
#   egress.interface  absent: the SNAT addresses sit on `uplink` (Ryza, by
#                     networkd). The nodes: a routeless dummy that
#                     forgejo-ephemeral-snat.service creates (taghmata/node.nix),
#                     so the cluster uplink's addresses never change.
#   egress.untrusted  chart name (`self.lib.lan.<name>`) of the dedicated SNAT
#                     address of this host's slots. Caddy on the guard tells
#                     slot traffic apart by it, so it is never a DNS host and
#                     the router must not lease it.
#   egress.trusted    null, or the chart name of a second SNAT address that
#                     only trusted runs use, after their credentials were
#                     delivered (forgejo-ephemeral-trusted-egress@<slot>). The
#                     guard's Caddy lets it reach Garage S3, Harbor and ntfy
#                     besides the forges and ncps (S3 through its own guard
#                     site, for trusted sources only). null: no address,
#                     units, rule, Caddy matcher or S3 site, or extra guest pins.
#   legacyVMs         stopped microVMs whose state is still on this host. The
#                     slot units cannot see their directories, nor those of any
#                     other microVM declared on the host.
#   dispatcher       machine that serves this host's slots; defaults to the
#                    slot host. The fleet sets this when remote dispatch is enabled.
#   slots.<name>     one per throwaway VM, with globally unique names.
#     index           1, 2, ...: tap `vm-eph-<index>`, MAC
#                     02:00:00:c1:00:<index + 2, hex>, subnet
#                     10.99.<index + 1>.0/24 (10.99.0 and 10.99.1 belong to the
#                     persistent CI guests, forgejo-runner-microvm.nix)
#     vcpu, memory    guest size, memory in GiB. A node slot leaves memory out:
#                     it is the node's forgejoRunner.resources.memory
#                     (asserted). The host slice allows one GiB
#                     more for QEMU and virtiofsd.
#     class           std (50 GiB overlay, 3 h runner) or large (150 GiB, 6 h).
#                     The overlay also holds Nix's build dir.
#     var             GiB for /var (workspace, TMPDIR, CARGO_HOME).
#
# The takeover (HOM-32 PR 12, operator flip; README "Ryza takeover"): the
# arguments below. Flip them here, never per machine: dispatcher and slot
# host must agree. Fixtures import this file with their own arguments.
#   takeover          off: everything as before. On: the ugalabugala and
#                     noosphere-user pools serve `takeoverLabels` for the
#                     owner's whole queue with a trust allowlist, ryza runs
#                     `ryzaSlots` std slots, and its persistent `nix-vm`
#                     guests and their CI credentials are gone.
#   takeoverLabels    ["nix-vm" "nix-eph"] (only the slots serve them), or
#                     with "nix" as well, shared with the node host runners
#                     until PR 13. Taking `nix` needs trustedJobs with
#                     trusted egress, or `untrustedTakeover` (asserted).
#   untrustedTakeover the operator's acknowledgement that, with `nix` taken
#                     and trust or trusted egress off, pilot's master publish
#                     fails and slot-run master builds don't reach ncps.
#   ryzaSlots         2 or 3. Each std slot's slice is 2 vCPU / 5 GiB; with
#                     Hermes's caps (gateway 6, dashboard 2 GiB) 2 slots
#                     commit 18 of ryza's 24 GiB and 3 commit 23. Use 3 only
#                     with `nix`, and check memory pressure after.
# The fleet module asserts the preconditions (forgejo-runner-ephemeral.nix).
#
# The three bare-metal nodes have independent operator gates (README "Large
# slots on Luna, Sol and Terra"). An unlisted node keeps its host runner and
# does not start a slot or claim either SNAT address.
{
  takeover ? true,
  # PR 13 prep (README "Large slots on Luna, Sol and Terra"): ryza's std slots
  # also take general `nix`, beside the node host runners, before any node
  # retires its runner. Trusted, with trusted egress (asserted).
  takeoverLabels ? ["nix" "nix-vm" "nix-eph"],
  untrustedTakeover ? false,
  ryzaSlots ? 2,
  nodes ? {},
}: let
  std = index: {
    inherit index;
    vcpu = 2;
    memory = 4;
    class = "std";
    var = 20;
  };
  nodeNames = ["luna" "sol" "terra"];
  nodeState = {
    hostRunnerEnabled ? true,
    slotsEnabled ? false,
    trustedEgress ? false,
    untrustedTakeover ? false,
  }: {inherit hostRunnerEnabled slotsEnabled trustedEgress untrustedTakeover;};
  nodeStates = assert builtins.all (name: builtins.elem name nodeNames) (builtins.attrNames nodes);
    builtins.listToAttrs (map (name: {
        inherit name;
        value = nodeState (nodes.${name} or {});
      })
      nodeNames);
  nodeHosts = builtins.mapAttrs (name: state: {
    uplink = "enp1s0";
    egress.interface = "dummy-ci-snat";
    egress.untrusted = "${name}-eph";
    egress.trusted =
      if state.trustedEgress
      then "${name}-eph-trusted"
      else null;
    slots."${name}-eph-1" = {
      index = 1;
      vcpu = 2;
      class = "large";
      var = 20;
      # memory: the CI share kubelet already reserves (system-reserved).
    };
  }) (builtins.removeAttrs nodeStates (builtins.filter (name: !nodeStates.${name}.slotsEnabled) (builtins.attrNames nodeStates)));
in {
  nodes = nodeStates;
  dispatcher = {
    # Prepare new PATs and a slotctl key before deploying this as true.
    remote = true;
    host = "cerberus";
    # Separate operator opt-in; applies to the dispatcher and its slots.
    trustedJobs = true;
    # Flip on Ryza before rolling out node slots (which always use this policy).
    # Off at merge to preserve the live Ryza service and slice definitions.
    protectStdSlots = true;
    # Provision the shared Garage key only with the remote dispatcher.
    sccacheCi = false;
    inherit takeover takeoverLabels untrustedTakeover;
    # Std uses takeoverLabels (or the pilot's labels); large slots replace
    # the user pool labels without changing scope, claim or credential IDs.
    largeLabels = {
      ugalabugala = ["nix" "nix-machines"];
      noosphere-user = ["nix" "nix-machines"];
    };
  };
  sccacheCiKey = rec {
    generatorName = "sccache-ci-garage-key";
    importSecret = "sccache-ci-s3-import";
    bucket = "sccache-ci";
    region = "main";
    endpointPrefix = "s3.${region}.garage";
  };
  guard = "cerberus";
  hosts =
    nodeHosts
    // {
      ryza = {
        uplink = "ens18";
        egress.untrusted = "ryza-eph";
        # Trusted runs SNAT to .240 (README "Trusted slot egress").
        egress.trusted = "ryza-eph-trusted";
        # The pre-HOM-29 single guest; its images may still be on disk. After
        # the takeover also the two retired `nix-vm` guests, until their state
        # is removed by hand (README "Ryza takeover").
        legacyVMs =
          ["ryza-ci"]
          ++ (
            if takeover
            then ["ryza-ci-ugalabugala" "ryza-ci-noosphere"]
            else []
          );
        # The slots take the nix-vm guests' 6 vCPU / 14 GiB. Today ryza
        # commits 14 + 5 (ryza-eph-1) + 8 (Hermes) = 27 GiB of caps on 24 GiB;
        # after the takeover 2 slots make it 18 (6 GiB left at peak for the
        # kernel, Blocky, tor, nix-daemon and sshd) and 3 make it 23 (about 1).
        # Caps, not reservations: the guests balloon.
        slots =
          {ryza-eph-1 = std 1;}
          // (
            if !takeover
            then {}
            else if ryzaSlots == 2
            then {ryza-eph-2 = std 2;}
            else if ryzaSlots == 3
            then {
              ryza-eph-2 = std 2;
              ryza-eph-3 = std 3;
            }
            else throw "_ci-slots.nix: ryzaSlots must be 2 or 3."
          );
      };
    };
}
