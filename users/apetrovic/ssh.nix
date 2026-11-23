{
  lib,
  self,
  ...
}: {
  # Shared by every workstation's home-manager config: home-configuration.nix
  # (NixOS) and home-configuration-darwin.nix (genetor).

  # ── SSH client config and public keys ────────────────────────────────────
  # Declarative so every workstation gets the same ~/.ssh/config instead of it
  # being copied between machines by hand and drifting.
  #
  # Only the PUBLIC halves live here. The private keys are held by the
  # Bitwarden SSH agent, which is why every IdentityFile below points at a
  # .pub: ssh offers the public key and the agent supplies the signature. A
  # machine without the agent running gets a working config and no ability to
  # authenticate -- the config alone is not enough.
  #
  # Deliberately NOT managed here: known_hosts (mutable, per-machine, and
  # home-manager would make it a read-only store symlink that ssh cannot
  # append to) and ~/.ssh/opentofu/id_rsa, which is a real private key and
  # must not go into the world-readable Nix store.
  programs.ssh = {
    enable = true;

    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/devzero.pub";
        identitiesOnly = true;
      };

      # Codilas self-hosted GitLab (natl/monorepo). Only the codilas key is
      # authorized there; unpinned, it can sort past MaxAuthTries in the agent.
      "gitlab.codilas.com" = {
        user = "git";
        port = 8022;
        identityFile = "~/.ssh/codilas.pub";
        identitiesOnly = true;
      };

      "forge.${self.lib.lab.domain}" = {
        hostname = self.lib.hosts.cerberus;
        port = 2222;
        # The wildcard *.ugalabugala.org record resolves to cerberus for every
        # name, so the IP is pinned above and the host-IP check would fail.
        checkHostIP = false;
        identityFile = "~/.ssh/apetrovic.pub";
        identitiesOnly = true;
      };

      # clan deploy targets (inventory/machines.nix). The Bitwarden agent holds
      # more keys than sshd's MaxAuthTries (6) allows offers for, and the only
      # key root accepts (clan.nix admin service) sorts 7th -- so without
      # pinning it here the connection is cut with "Too many authentication
      # failures" before that key is ever tried. clan overwrites NIX_SSHOPTS
      # with its own options, so ssh_config is the only place this can be set
      # for `clan machines update`.
      #
      # Keep the addresses in step with inventory/machines.nix: a target that
      # is missing from this list silently reverts to the failure above.
      "clan-targets" = {
        host = lib.concatStringsSep " " [
          "localhost"
          "127.0.0.1"
          "::1"
          "phalanx"
          "enginseer"
          "genetor"
          "cerberus"
          "cypramundi"
          "terra"
          "luna"
          "sol"
          "servitor"
          self.lib.hosts.phalanx # phalanx
          self.lib.hosts.enginseer # enginseer
          self.lib.hosts.servitor # servitor
          self.lib.hosts.genetor
          self.lib.hosts.cerberus # cerberus
          self.lib.hosts.terra # terra
          self.lib.hosts.luna
          self.lib.hosts.sol
          self.lib.hosts.mars # mars
          self.lib.hosts.cypramundi # cypramundi
          self.lib.hosts.alfrost # alfrost
        ];
        identityFile = "~/.ssh/apetrovic.pub";
        identitiesOnly = true;
      };
    };
  };

  home.file = {
    ".ssh/apetrovic.pub".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuTvHKw/dHSm0NLjCQsk/9sPyNRerLB/wWuwitVpvdg
    '';
    ".ssh/devzero.pub".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM5HUXziQ+9jPfnqvCmd4MAIyMolk3EfDdGgHta8kEDM devzero
    '';
    ".ssh/codilas.pub".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3Mce+RNo8zHxm3IPryIOfiVl1rvqejZHsm+9BFdPFX codilas
    '';
    ".ssh/forgejo.pub".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/JTrEMUUkts8LUq0JKzqcQIr/t7k26jjlq7nVNxnFq forgejo
    '';
  };
}
