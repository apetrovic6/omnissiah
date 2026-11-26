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
#     vcpu, memory    guest size, memory in GiB. The host slice allows one GiB
#                     more for QEMU and virtiofsd.
#     class           std (50 GiB overlay, 3 h runner) or large (150 GiB, 6 h).
#                     The overlay also holds Nix's build dir.
#     var             GiB for /var (workspace, TMPDIR, CARGO_HOME).
#
# takeover (HOM-32 PR 12, operator flip; README "Ryza takeover"): the
# argument below. Off, everything is as before. On, the ugalabugala and
# noosphere-user pools take the `nix`, `nix-vm` and `nix-eph` labels for
# the owner's whole queue with a trust allowlist, ryza gets three std slots,
# and its persistent `nix-vm` guests and their CI credentials are gone. The
# fleet module asserts the preconditions (forgejo-runner-ephemeral.nix).
# Flip it here, never per machine: dispatcher and slot host must agree.
# Fixtures import this file with `{takeover = true;}`.
{takeover ? false}: let
  std = index: {
    inherit index;
    vcpu = 2;
    memory = 4;
    class = "std";
    var = 20;
  };
in {
  dispatcher = {
    # Prepare new PATs and a slotctl key before deploying this as true.
    remote = true;
    host = "cerberus";
    # Separate operator opt-in; applies to the dispatcher and its slots.
    trustedJobs = false;
    # Provision the shared Garage key only with the remote dispatcher.
    sccacheCi = false;
    inherit takeover;
  };
  sccacheCiKey = rec {
    generatorName = "sccache-ci-garage-key";
    importSecret = "sccache-ci-s3-import";
    bucket = "sccache-ci";
    region = "main";
    endpointPrefix = "s3.${region}.garage";
  };
  guard = "cerberus";
  hosts.ryza = {
    uplink = "ens18";
    egress.untrusted = "ryza-eph";
    # "ryza-eph-trusted" once the hand steps in the README are done.
    egress.trusted = null;
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
    # Three std slots take the nix-vm guests' 6 vCPU / 14 GiB: 6 vCPU of
    # quota and 15 GiB of slices on ryza's 8 vCPU / 24 GiB, down from 8 and
    # 19 GiB with the guests, leaving 2 vCPU and 9 GiB for the host and
    # Hermes. A fourth would commit all 8 vCPU and 20 GiB.
    slots =
      {ryza-eph-1 = std 1;}
      // (
        if takeover
        then {
          ryza-eph-2 = std 2;
          ryza-eph-3 = std 3;
        }
        else {}
      );
  };
}
