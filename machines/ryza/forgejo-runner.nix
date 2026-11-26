# One CI microVM per forge so jobs do not share a kernel with one another
# or with the agent's logins on this host.
#
# On trial under its own label: a workflow opts in with `runs-on: nix-vm`.
# Once it has proven itself, it takes the shared `nix` label and cerberus's
# runner goes.
#
# Registering (after the first deploy's `clan vars generate ryza`):
#   nix run .#forgejo-runner-register -- ryza
{
  config,
  self,
  ...
}: let
  slotOnly = config.services.imperium.forgejoEphemeral.remoteDispatcher.enable;
in {
  imports = [
    self.nixosModules.forgejo-runner-microvm
    self.nixosModules.sccache
  ];

  services.imperium.forgejoRunner = {
    # These guests load the same CI upload credentials we are moving off Ryza.
    enable = !slotOnly;
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

  services.imperium.sccache.enable = !slotOnly;
}
