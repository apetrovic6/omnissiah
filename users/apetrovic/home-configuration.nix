{
  pkgs,
  self,
  lib,
  config,
  osConfig,
  ...
}: let
  # sccache on garage-main. The NixOS half (generator, credentials owner,
  # wrapper on the system path) is in modules/rites/sccache.nix and
  # stc/workstation.nix; the values are read through osConfig so the
  # machines and the bucket cannot drift apart. The wrapper scrubs what
  # used to need a separate sccache-garage script here: it unsets
  # CARGO_INSTALL_ROOT (devenv exports it per checkout, and sccache 0.19
  # hashes it into every cache key) and the ambient AWS_* variables that
  # reqsign's env provider would otherwise prefer over the credentials
  # file, and it defaults AWS_SHARED_CREDENTIALS_FILE to this machine's
  # deployed var file -- scoped to sccache's own process tree, so the aws
  # CLI and other AWS SDK tools in the session keep their own credentials.
  sccacheCfg = osConfig.services.imperium.sccache;
in {
  imports = [
    # self.inputs.magos.homeManagerModules.default
    self.inputs.magos.homeModules.skills
    self.inputs.magos.homeModules.herdr
    self.inputs.omnishell.homeManagerModules.default

    ./git.nix
    ./firefox
    ./ssh.nix
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
  #   image = ../../relics/wallpapers/everforest/1.png; # optional
  #   # image = ../../relics/wallpapers/everforest/1.png; # optional
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

  programs.git.settings.url."git@github.com:devzero-inc/".insteadOf = "https://github.com/devzero-inc/";

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

  # Agent Skills from magos (the herdr orchestration skill, so far) for Claude
  # Code, pi and omp at once, and herdr's Claude Code lifecycle integration.
  # pi's and omp's herdr integrations come with magos.agents.pi / .omp in
  # stc/workstation.nix.
  magos.skills.enable = true;
  magos.herdr.claude.enable = true;

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
        url = "https://kaneo.${self.lib.lab.domain}/api/mcp";
      };
    };
  };

  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    # enableZshIntegration = true;
  };

  # ── sccache: shared compile cache in the `sccache` bucket on garage-main ──
  #
  # Here rather than in environment.sessionVariables (stc/workstation.nix):
  # this is user environment. Session variables in the NixOS module leak to
  # every user, every service and every root shell -- which cannot even read
  # the 0400 user-owned credentials file -- while home.sessionVariables is
  # scoped to apetrovic's sessions, which is exactly where cargo runs
  # (terminals, devenv shells, and the agent worktrees inherit them too).
  #
  # The endpoint is the LAN/VPN VIP only (no Pangolin route, by decision), and
  # SCCACHE_IGNORE_SERVER_IO_ERROR=1 is what keeps a build away from home, or
  # during a Garage outage, working -- uncached instead of failed.
  home.packages = [
    # The wrapper under the name `sccache`, replacing the old bare client +
    # sccache-garage pair: a bare `sccache --show-stats` in a fresh shell
    # autostarts the daemon on 127.0.0.1:4226, and without credentials (or
    # with the omnissiah .envrc's AWS_*) that server then serves every
    # later client -- cargo included -- until its idle timeout. There must
    # be no plain invocation that can start it.
    sccacheCfg.wrapper
  ];

  home.sessionVariables = {
    RUSTC_WRAPPER = "${sccacheCfg.wrapper}/bin/sccache";
    SCCACHE_BUCKET = sccacheCfg.bucket;
    SCCACHE_ENDPOINT = sccacheCfg.endpoint;
    SCCACHE_REGION = sccacheCfg.region;
    SCCACHE_IGNORE_SERVER_IO_ERROR = "1";
    # sccache 0.19 strips basedirs from C-family cache keys only (rust.rs
    # never reads them; Rust keys hash cwd, argument paths and CARGO_* env
    # verbatim), so this helps build-script cc compilations (ring, aws-lc-sys,
    # zstd-sys, ...) hit across worktrees under ~/programming, and does
    # nothing for -- and nothing to, Rust.
    SCCACHE_BASEDIRS = "/home/apetrovic/programming";
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
