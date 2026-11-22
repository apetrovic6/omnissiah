# CI runner for both forges, in a microVM (modules/rites/forgejo-runner-microvm.nix)
# so jobs never share a kernel with the agent's logins on this host.
#
# On trial under its own label: a workflow opts in with `runs-on: nix-vm`.
# Once it has proven itself, it takes the shared `nix` label and cerberus's
# runner goes.
#
# Registering (after the first deploy's `clan vars generate ryza`):
#   nix run .#forgejo-runner-register -- ryza
{self, ...}: {
  imports = [
    self.nixosModules.forgejo-runner-microvm
    self.nixosModules.sccache
  ];

  services.imperium.forgejoRunner = {
    enable = true;
    isolation = "microvm";
    labels = ["nix-vm:host"];
    # The VM's size. ryza has 24 GiB; the rest is for the agent and the host.
    resources = {
      cpus = 6;
      memory = 14;
    };
    microvm.uplink = "ens18";
  };
  services.imperium.sccache.enable = true;
}
