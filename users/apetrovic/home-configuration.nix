{
  pkgs,
  self,
  lib,
  config,
  osConfig,
  ...
}: let
  atticToken =
    osConfig.clan.core.vars.generators.attic-pull-token.files.token.path;

  atticSubstituter =
    osConfig.clan.core.vars.generators.attic-pull-token.files.attic-substituter.path;
in {
  imports = [
    # self.inputs.magos.homeManagerModules.default
    self.inputs.omnishell.homeManagerModules.default

    ./firefox
  ];

  nixpkgs.overlays = [
    self.overlays.bitwarden-desktop
  ];

  nixpkgs.config.permittedInsecurePackages = ["electron-39.8.10"];

  # PipeASIO (Rocksmith, via nixos-rocksmith overlay applied to HM's own
  # nixpkgs) builds against Wine's MSVC cross-toolchain → xwin-fetch-msvc
  # requires accepting the Microsoft VS license terms.
  nixpkgs.config.microsoftVisualStudioLicenseAccepted = true;

  # omnishell's HM module switches on programs.helix with a helix from its OWN
  # flake input (github:apetrovic6/helix) rather than pkgs.helix, so
  # self.overlays.helix never reaches it. The result was a second, unconfigured
  # editor built and installed next to the magos-wrapped helix that
  # stc/workstation.nix already puts in systemPackages -- two full helix builds
  # per rebuild, and whichever won $PATH decided which config you got.
  # `hx` still resolves after this, to the magos build.
  programs.helix.enable = lib.mkForce false;

  xdg = {
    enable = true;
  };

  # home.packages = with pkgs; [];

  nix = {
    extraOptions = ''
      always-allow-substitutes = true
    '';

    settings = {
      netrc-file = /home/apetrovic/.config/nix/netrc;
      trusted-users = ["root" "apetrovic"];
      # No trusted-public-keys here. A user nix.conf replaces the system list
      # instead of extending it, and as a trusted user the daemon honours it,
      # so any list here silently drops ncps's key (stc/base.nix) and every
      # ncps substitute is rejected as "not signed by any of the keys".
    };
  };

  programs.bash.initExtra = ''
    export SSH_AUTH_SOCK=/home/apetrovic/.bitwarden-ssh-agent.sock
  '';

  # magos.hyprland.hm = {
  #   input = {
  #     kbLayouts = ["us" "hr"];
  #   };
  # };

  # magos.hm.core.swayosd.enable = false;
  # magos.hm.core.swaync.enable = false;
  # magos.hm.core.waybar.enable = false;
  # magos.hm.hyprlock.enable = false;

  # magos.hm.noctalia.enable = true;

  # programs.noctalia-shell = {
  #   settings = {
  #     # bar.backgroundOpacity = lib.mkForce 0.0;
  #     location = {
  #       name = "Zagreb";
  #     };
  #   };
  # };

  # magos.hm.stylix = {
  #   enable = true;
  #   image = ../../wallpapers/everforest/1.png; # optional
  #   # image = ../../wallpapers/everforest/1.png; # optional
  #   polarity = "dark";
  #   base16Scheme = "everforest-dark-soft";

  #   targets.firefox.profileNames = ["apetrovic"];
  # };

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "apetrovic";
  home.homeDirectory = "/home/apetrovic";

  programs.obsidian.enable = true;

  nixpkgs.config.allowUnfree = true;

  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      user = {
        name = "apetrovic";
        email = "petrovicante6@gmail.com";
      };

      init.defaultBranch = "master";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rebase.autoStash = true;

      url."git@github.com:devzero-inc/".insteadOf = "https://github.com/devzero-inc/";
    };
  };

  programs.btop.enable = true;

  # Shared MCP servers -- ONE declaration, both agents.
  #
  # This writes ~/.config/mcp/mcp.json, which is:
  #   - merged into Claude Code's own config by the claude-code module
  #     (programs.claude-code.mcpServers wins on a name clash), and
  #   - step 1 of pi-mcp-adapter's precedence chain, where "later entries
  #     win" means the layers are MERGED, not replaced -- so this sits
  #     underneath pi's agent-dir mcp.json (kaneo, devenv, from magos) rather
  #     than being shadowed by it.
  #
  # Anything needed by only one of the two still belongs in that agent's own
  # config; this is for servers both should see.
  programs.mcp = {
    enable = true;

    servers = {
      # Real NixOS data for the agents: package and option search, home-manager,
      # nix-darwin, nixvim, nixarchy, flake inputs, binary-cache status. Stdio,
      # so it runs on demand as a child process -- nothing listening, no
      # credentials, and no network until a tool call is made (it then queries
      # search.nixos.org and the official docs).
      #
      # Named `nixos` deliberately: upstream keeps that as the client key across
      # the rename from mcp-nixos, so tools surface as mcp__nixos__* and stay
      # stable if the package is renamed again.
      nixos.command = lib.getExe self.inputs.mcp-nixarchy.packages.${pkgs.stdenv.hostPlatform.system}.mcp-nixarchy;
    };
  };

  programs.claude-code = {
    enable = true;
    # claude-code itself comes from environment.systemPackages in
    # stc/workstation.nix; only manage its config here.
    package = null;

    mcpServers = {
      opsee = {
        type = "http";
        url = "https://mcp.api.opsee.ai/mcp";
      };

      # Kaneo task tracker on cerberus (machines/cerberus/kaneo.nix). Auth is
      # OAuth 2.1 + PKCE with dynamic client registration, so there is no token
      # to store here -- run `/mcp` once to authorise. LAN/VPN only: the vhost
      # is deliberately not published through Pangolin, so this server shows as
      # failed when off-network.
      kaneo = {
        type = "http";
        url = "https://kaneo.ugalabugala.org/api/mcp";
      };
    };
  };

  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    # enableZshIntegration = true;
  };

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

      "forge.ugalabugala.org" = {
        hostname = "192.168.1.105";
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
          "192.168.1.75" # phalanx
          "192.168.1.146" # enginseer
          "192.168.1.13" # servitor
          "192.168.1.109"
          "192.168.1.105" # cerberus
          "192.168.1.138" # terra
          "192.168.1.232"
          "192.168.1.42"
          "192.168.1.44" # mars
          "152.53.34.16" # cypramundi
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
    ".ssh/forgejo.pub".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/JTrEMUUkts8LUq0JKzqcQIr/t7k26jjlq7nVNxnFq forgejo
    '';
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
