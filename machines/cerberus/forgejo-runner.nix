# Shared runner setup and registration flow: modules/rites/forgejo-runner.nix.
# sccache: host-step cargo builds cache into the `sccache` bucket on garage-main
# (modules/rites/sccache.nix).
{self, ...}: {
  imports = [
    self.nixosModules.forgejo-runner
    self.nixosModules.sccache
  ];

  services.imperium.forgejoRunner = {
    enable = true;
    # Uncapped, a CI build took 12.7 of cerberus's 14.6 GiB on 2026-11-09 and
    # the VM thrashed (no swap, OOM killer never fired) until reset from
    # Proxmox. Forgejo, Caddy, Technitium and the rest need what is left.
    resources = {
      cpus = 3;
      memory = 8;
    };
  };
  services.imperium.sccache.enable = true;
}
