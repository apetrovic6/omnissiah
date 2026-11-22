# The always-on agent (modules/rites/hermes.nix), on the host side of ryza.
# CI runs in its own microVM (./forgejo-runner.nix), so jobs never share a
# kernel with the logins in /var/lib/hermes. The VM takes 14 of ryza's 24 GiB;
# the gateway is capped at 6.
#
# API keys: the DeepSeek and Qwen keys pi already uses (shared var
# pi-api-keys), by default. Hermes-only ones go in `secrets`, one prompt each:
#   secrets = ["OPENROUTER_API_KEY"];
#   clan vars generate ryza --generator hermes-openrouter-api-key --regenerate
{self, ...}: let
  inherit (import ../../modules/cartographa/_cartographa.nix) noosphere lab;
in {
  imports = [self.nixosModules.hermes];

  services.imperium.hermes = {
    enable = true;
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
}
