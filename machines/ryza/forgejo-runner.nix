# One CI microVM per forge so jobs do not share a kernel with one another
# or with the agent's logins on this host.
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
    self.nixosModules.forgejo-runner-ephemeral
    self.nixosModules.sccache
  ];

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

  # Enroll the dedicated PAT before enabling the one-job pilot (see README).
  services.imperium.forgejoEphemeral = {
    enable = true;
    pools.ugalabugala = {
      forge = "ugalabugala";
      scope.user = "manjo";
      labels = ["nix-eph"];
      dispatch = [9];
      trust = {
        repos."9" = {
          owner = "manjo";
          name = "rust-app-template";
        };
        users = ["manjo"];
      };
    };
    # forge.noosphere.uk, one PAT for both pools (var forgejo-ephemeral-noosphere).
    # Only jobs that ask for `runs-on: nix-eph` come here until the label takeover (HOM-32 PR 12).
    pools.noosphere-user = {
      forge = "noosphere";
      scope.user = "manjo";
      labels = ["nix-eph"];
      # manjo/auspex, manjo/mushroom-farmer
      dispatch = [221 188];
    };
    # monolith-softworks is not public, so its repo IDs aren't listed here: every org repo
    # (inanna, tally, and any later one) is dispatched untrusted.
    pools.noosphere-org = {
      forge = "noosphere";
      scope.org = "monolith-softworks";
      labels = ["nix-eph"];
      dispatch = "owner";
    };
  };

  services.imperium.sccache.enable = true;
}
