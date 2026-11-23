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
  hasHostPin = knownHosts != "";
  hostKeyAlgorithm = builtins.head (lib.splitString " " knownHosts);
in {
  imports = [
    self.nixosModules.hermes
    ../../modules/rites/_hermes-stygies-ssh.nix
  ];

  options.services.imperium.hermes.stygies.knownHosts = lib.mkOption {
    type = lib.types.str;
    description = "Verified stygies SSH host public key (type and base64, without a hostname). Empty disables coder.";
    # stygies's own host key, from the clan var its sshd was deployed with,
    # so the pin follows a reinstall instead of going stale. The value ends in
    # an empty comment; keep only the type and the key. Empty (coder off)
    # until the var exists.
    default = let
      pub = self.lib.vars.machine "stygies" "openssh" "ssh.id_ed25519.pub";
    in
      if builtins.pathExists pub
      then lib.concatStringsSep " " (lib.take 2 (lib.filter (s: s != "") (lib.splitString " " (lib.trim (builtins.readFile pub)))))
      else "";
  };

  config = {
    assertions = [
      {
        assertion = !hasHostPin || hostKeyAlgorithm == "ssh-ed25519";
        message = "services.imperium.hermes.stygies.knownHosts must be an ssh-ed25519 host key.";
      }
    ];

    # Keep the identity unavailable to the default profile's local terminal
    # until stygies is pinned. Clan can still generate the public half.
    clan.core.vars.generators.hermes-stygies-ssh.files."id_ed25519" = let
      keyOwner =
        if hasHostPin
        then "hermes"
        else "root";
    in {
      owner = lib.mkForce keyOwner;
      group = lib.mkForce keyOwner;
    };

    programs.ssh = lib.mkIf hasHostPin {
      knownHosts.stygies = {
        hostNames = [stygies];
        publicKey = knownHosts;
      };
      # A key accepted before the pin was deployed must not override it.
      # The system block assumes ~/.ssh/config does not override it: OpenSSH
      # reads the user's config first.
      extraConfig = ''
        Host ${stygies}
          UserKnownHostsFile none
          HostKeyAlgorithms ${hostKeyAlgorithm}
      '';
    };
    services.imperium.hermes = {
      enable = true;
      extraPackages = lib.optional hasHostPin pkgs.openssh;
      profiles.coder = {
        # Hermes uses accept-new. Without a system pin, don't expose a profile
        # that could trust an unknown host or run its terminal locally on ryza.
        enable = hasHostPin;
        soul = builtins.readFile ./hermes-coder-soul.md;
        # One Matrix room per project, all handled by this profile: each room is
        # its own conversation, and a thread per task gives a fresh one inside
        # it. Invite @hermes, then add the room's Internal room ID (Element:
        # room settings, Advanced), e.g. pilot = "!abc:matrix.example.org".
        rooms = {
          tally = "!vR9D2BaWBsjdrDlBt6Vb7_iEKpj4iEny5tRPOnzVUv0";
          rust-app-template = "!qfeHKyEuU37YpF4mms2eyiISUIbyx8ajidvKeQn3b-c";
        };
        settings.terminal = {
          backend = "ssh";
          ssh_host = stygies;
          ssh_user = "hermes";
          ssh_key = config.clan.core.vars.generators.hermes-stygies-ssh.files."id_ed25519".path;
          cwd = "~/work";
        };
        # Kaneo uses browser PKCE. Port 28431 is outside both hosts' ephemeral
        # ranges; keep it fixed for the phalanx-to-ryza SSH tunnel.
        settings.mcp_servers.kaneo = {
          url = "https://kaneo.${self.lib.lab.domain}/api/mcp";
          auth = "oauth";
          oauth.redirect_port = 28431;
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
