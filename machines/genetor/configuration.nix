{
  pkgs,
  self,
  lib,
  config,
  ...
}: {
  imports = [
    self.inputs.nix-homebrew.darwinModules.nix-homebrew
    ../../users/apetrovic/home-darwin.nix
    self.inputs.magos.darwinModules.claude-accounts
  ];

  # Per-session Claude subscription (`claude-as <id>`); see stc/workstation.nix.
  magos.claudeAccounts = {
    enable = true;
    accounts = {
      main.label = "Personal";
      devzero.label = "DevZero";
      codilas.label = "Codilas";
    };
  };

  nixpkgs.config = {allowUnfree = true;};

  nixpkgs.overlays = [
    self.overlays.helix
    self.overlays.herdr
  ];

  system.primaryUser = "apetrovic";
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "apetrovic";
    # Optional: Declarative tap management
    taps = {
      "homebrew/homebrew-core" = self.inputs.homebrew-core;
      "homebrew/homebrew-cask" = self.inputs.homebrew-cask;
      # "quickemu-project/homebrew-quickemu" = self.inputs.homebrew-quickemu;
    };

    # Optional: Enable fully-declarative tap management
    #
    # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
    mutableTaps = false;
    autoMigrate = true;
  };
  homebrew = {
    enable = true;
    brews = [
      "mas"
      # "quickemu"
    ];
    casks = [
      "ghostty"
      "bambu-studio"
      "steinberg-download-assistant"
      "steinberg-library-manager"
      "ilok-license-manager"
      "microsoft-teams"
      "native-access"
      # No "librewolf": programs.librewolf (users/apetrovic/firefox) installs
      # it. NEVER let cleanup = "zap" remove a librewolf cask: its zap trashes
      # ~/Library/Application Support/LibreWolf, which on case-insensitive
      # APFS is the home-manager profile directory. `brew uninstall --cask`
      # (no --zap) by hand first.
    ];
    onActivation = {
      cleanup = "zap";
      # Off: pkg-based casks (native-access, ilok-license-manager,
      # steinberg-*) need sudo to upgrade, and activation has no terminal to
      # prompt on, so `brew bundle` failed every deploy with a pending update.
      # Upgrade by hand with `brew upgrade` in a terminal on the Mac.
      upgrade = false;
      autoUpdate = true;
    };

    masApps = {
      # "Xcode" = 497799835;
      #"Tailscale" = 1475387142;
      # "LocalSend" = 1661733229;
    };

    taps = builtins.attrNames config.nix-homebrew.taps;
  };

  environment.systemPackages = with pkgs; [
    git
    # `fj`, the Forgejo CLI (repos, PRs, issues, Actions) for both forges.
    # Log in once per machine with `fj -H <forge> auth login` (browser), or
    # `fj -H <forge> auth add-token` with a token on stdin.
    forgejo-cli
    wget
    vim
    fastfetch
    yazi
    brave
    obsidian
    bitwarden-desktop
    localsend
    devenv
    claude-code
    xcodes
    helix
    herdr
    podman
    podman-desktop
    kubectl
    # Real Docker CLI + compose, talking to podman through /var/run/docker.sock
    # (see docker-socket below) -- more faithful than a docker->podman alias.
    docker-client
    docker-compose
  ];

  # Podman on macOS runs containers in a Linux VM (`podman machine`); nixpkgs'
  # podman already bundles the darwin VM helpers (gvproxy, vfkit, krunkit) in
  # libexec/podman. nix-darwin has no podman module, so this login agent does
  # the one imperative part: create the VM on first run, then start it at
  # every login. Rootful because kind's podman provider (nautili's devenv sets
  # KIND_EXPERIMENTAL_PROVIDER=podman) needs it. Sizing is for the 16 GiB M1
  # Pro; changing it here does not resize an existing VM -- use
  # `podman machine set` (stop the machine first).
  launchd.user.agents.podman-machine = {
    path = [pkgs.podman "/usr/bin" "/bin" "/usr/sbin" "/sbin"];
    script = ''
      if ! podman machine inspect podman-machine-default >/dev/null 2>&1; then
        podman machine init --cpus 4 --memory 6144 --disk-size 60 --rootful
      fi
      podman machine start || true # already running is an error, not a failure

      # The API socket lives under $TMPDIR, which differs per session; record
      # it at a fixed path for the docker-socket daemon to link to.
      sock=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')
      ln -sfn "$sock" /Users/apetrovic/.local/share/containers/podman/machine/docker.sock
    '';
    serviceConfig = {
      RunAtLoad = true;
      # `podman machine start` daemonises vfkit + gvproxy and exits; without
      # this, launchd kills the job's whole process group on exit and the VM
      # dies right after "started successfully".
      AbandonProcessGroup = true;
      StandardOutPath = "/Users/apetrovic/Library/Logs/podman-machine.log";
      StandardErrorPath = "/Users/apetrovic/Library/Logs/podman-machine.log";
    };
  };

  # Docker compatibility: what `sudo podman-mac-helper install` would do (it is
  # not packaged in nixpkgs). macOS wipes /var/run at boot, so a root daemon
  # recreates the symlink every boot; it may dangle until the podman-machine
  # agent has started the VM at login, which is harmless.
  launchd.daemons.docker-socket = {
    script = ''
      ln -sfn /Users/apetrovic/.local/share/containers/podman/machine/docker.sock /var/run/docker.sock
    '';
    serviceConfig.RunAtLoad = true;
  };

  nix.enable = false;

  # Lix (install.lix.systems) owns /etc/nix/nix.conf, so nix.settings is inert
  # here; its nix.conf `!include`s nix.custom.conf, which we manage instead.
  # ncps (Priority 10) is tried before cache.nixos.org (40), which stays in
  # `substituters` as the fallback. ncps is LAN/VPN only, so the short
  # connect-timeout keeps fetches away from home from stalling on it. The
  # nix-daemon only reads this at start: restart it after a change.
  environment.etc."nix/nix.custom.conf" = {
    # The installer's original file (a comment header only), so the first
    # activation may replace it.
    knownSha256Hashes = ["a6dee4985bf207d3bec6a3cee28aefb33e60f5d0a91d8c20bbd71b9dadb2e601"];
    text = ''
      extra-substituters = https://ncps.noosphere.uk
      extra-trusted-public-keys = ${lib.removeSuffix "\n" (builtins.readFile (self.lib.vars.shared "ncps-signing-key" "ncps-signing-key.pub"))}
      connect-timeout = 5
    '';
  };

  fonts.packages = [
    pkgs.nerd-fonts.fira-code
    pkgs.nerd-fonts.fira-mono
    pkgs.nerd-fonts.hack
    pkgs.nerd-fonts.jetbrains-mono
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuTvHKw/dHSm0NLjCQsk/9sPyNRerLB/wWuwitVpvdg"
  ];

  system.stateVersion = 6;

  clan.core.networking.targetHost = "root@192.168.1.149";
  nixpkgs.hostPlatform = "aarch64-darwin";

  services.tailscale = {
    enable = true;
    overrideLocalDns = true;
  };

  system.defaults = {
    dock.autohide = true;

    dock.persistent-apps = [
      "System/Applications/Mail.app"
      "System/Applications/Notes.app"
      "System/Applications/Reminders.app"
      "System/Applications/App Store.app"
      "/Applications/Librewolf.app"
      "/Applications/Ghostty.app"
      "/Applications/Cubase 14.app"
      "System/Applications/System Settings.app"
    ];

    loginwindow.GuestEnabled = false;
  };
}
