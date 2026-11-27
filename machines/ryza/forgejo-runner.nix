# One CI microVM per forge so jobs do not share a kernel with one another
# or with the agent's logins on this host.
#
# On trial under its own label: a workflow opts in with `runs-on: nix-vm`.
# It stays on that label until the ephemeral label takeover (HOM-32 PR 12):
# with `takeover` on in modules/rites/_ci-slots.nix, both guests, their
# runner registrations and ryza's shared CI credentials (the guests'
# sccache key, CI signing key and ncps netrc) are gone, and the one-job
# slots serve `nix-vm` (README "Ryza takeover").
#
# Registering (after the first deploy's `clan vars generate ryza`):
#   nix run .#forgejo-runner-register -- ryza
args @ {
  self,
  lib,
  ...
}: let
  # The shared fleet data, as the ephemeral fleet module reads it.
  takeover = (args.ciDispatcher or self.lib.ciDispatcher).takeover or false;
in {
  imports = lib.optionals (!takeover) [
    self.nixosModules.forgejo-runner-microvm
    self.nixosModules.sccache
  ];

  config = lib.optionalAttrs (!takeover) {
    services.imperium.forgejoRunner = {
      enable = true;
      isolation = "microvm";
      labels = ["nix-vm:host"];
      # Combined guest budget. Ryza has 24 GiB; the rest is for the agent and
      # host, including the hypervisor overhead.
      resources = {
        cpus = 6;
        memory = 14;
      };
      microvm.uplink = "ens18";
    };

    services.imperium.sccache.enable = true;
  };
}
