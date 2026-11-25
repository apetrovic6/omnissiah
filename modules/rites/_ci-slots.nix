# The nix-eph slot inventory: which machines run throwaway Forgejo CI VMs, and
# what each slot looks like. Plain data, like the network chart
# (modules/cartographa/_chart.nix), read as `self.lib.ciSlots` by the slot
# module (forgejo-runner-ephemeral.nix), by cerberus's Caddy guard
# (machines/cerberus/proxy.nix) and by the slot hosts' network config, so none
# of them evaluates another machine's configuration.
#
#   uplink            the host interface slot traffic is source-NATed out of
#   egress.untrusted  chart name (`self.lib.lan.<name>`) of the dedicated SNAT
#                     address of this host's slots. Caddy on cerberus tells slot
#                     traffic apart by it, so it is never a DNS host and the
#                     router must not lease it.
#   legacyVMs         stopped microVMs whose state is still on this host. The
#                     slot units cannot see their directories, nor those of any
#                     other microVM declared on the host.
#   dispatcher       machine that serves this host's slots; defaults to the
#                    slot host. A different machine uses forced-command SSH.
#   slots.<name>     one per throwaway VM, with globally unique names.
#     index           1, 2, ...: tap `vm-eph-<index>`, MAC
#                     02:00:00:c1:00:<index + 2, hex>, subnet
#                     10.99.<index + 1>.0/24 (10.99.0 and 10.99.1 belong to the
#                     persistent CI guests, forgejo-runner-microvm.nix)
#     vcpu, memory    guest size, memory in GiB. The host slice allows one GiB
#                     more for QEMU and virtiofsd.
#     overlay, var    GiB of the sparse per-job disk images: the writable store
#                     plus Nix build dir, and /var (workspace, TMPDIR,
#                     CARGO_HOME)
{
  ryza = {
    uplink = "ens18";
    egress.untrusted = "ryza-eph";
    # The pre-HOM-29 single CI guest; its images may still be on disk.
    legacyVMs = ["ryza-ci"];
    slots.ryza-eph-1 = {
      index = 1;
      vcpu = 2;
      memory = 4;
      overlay = 50;
      var = 20;
    };
  };
}
