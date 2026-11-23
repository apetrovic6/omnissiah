# The always-on agent (modules/rites/hermes.nix), on the host side of ryza.
# CI runs in its own microVM (./forgejo-runner.nix), so jobs never share a
# kernel with the logins in /var/lib/hermes. The VM takes 14 of ryza's 24 GiB;
# the gateway is capped at 6.
#
# API keys: the DeepSeek and Qwen keys pi already uses (shared var
# pi-api-keys), by default. Hermes-only ones go in `secrets`, one prompt each:
#   secrets = ["OPENROUTER_API_KEY"];
#   clan vars generate ryza --generator hermes-openrouter-api-key --regenerate
{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (import ../../modules/cartographa/_cartographa.nix) noosphere lab;
  inherit (self.lib.hosts) stygies;
  inherit (config.services.imperium.hermes.stygies) knownHosts;
in {
  imports = [
    self.nixosModules.hermes
    ../../modules/rites/_hermes-stygies-ssh.nix
  ];

  options.services.imperium.hermes.stygies.knownHosts = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Verified stygies SSH host public key (type and base64, without a hostname). Empty disables coder.";
  };

  config = {
    programs.ssh = lib.mkIf (knownHosts != "") {
      knownHosts.stygies = {
        hostNames = [stygies];
        publicKey = knownHosts;
      };
      # A key accepted before the pin was deployed must not override it.
      extraConfig = ''
        Host ${stygies}
          UserKnownHostsFile none
      '';
    };
    services.imperium.hermes = {
      enable = true;
      extraPackages = [pkgs.openssh];
      profiles.coder = {
        # Hermes uses accept-new. Without a system pin, don't expose a profile
        # that could trust an unknown host or run its terminal locally on ryza.
        enable = knownHosts != "";
        # Set to the Matrix room ID once the bot has been invited.
        chatId = null;
        settings.terminal = {
          backend = "ssh";
          ssh_host = stygies;
          ssh_user = "hermes";
          ssh_key = config.clan.core.vars.generators.hermes-stygies-ssh.files."id_ed25519".path;
          cwd = "~/work";
        };
      };
      dashboard = {
        enable = true;
        publicUrl = "https://hermes.${noosphere.domain}";
        oidc.issuer = "https://id.${noosphere.domain}";
        # The cluster nodes: Traefik's traffic arrives from whichever one its
        # pod runs on.
        allowedSources = with self.lib.hosts; [terra luna sol mars];
      };
      # @hermes on the lab homeserver, registered on cypramundi
      # (services.imperium.matrixBots there). DM it from Element.
      matrix = {
        enable = true;
        inherit (lab.matrix) homeserver serverName;
        allowedUsers = ["@kumamte:${lab.matrix.serverName}"];
      };
    };
  };
}
