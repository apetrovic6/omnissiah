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
    ];
    casks = [
      "ghostty"
      "bambu-studio"
      # "steinberg-download-assistant"
      # "steinberg-library-manager"
      # "ilok-license-manager"
      # "microsoft-teams"
      # "native-access"
    ];
    onActivation = {
      cleanup = "zap";
      upgrade = true;
      autoUpdate = true;
    };

    masApps = {
      "Xcode" = 497799835;
      "Tailscale" = 1475387142;
      #"LocalSend" = 1661733229;
    };

    taps = builtins.attrNames config.nix-homebrew.taps;
  };

  environment.systemPackages = with pkgs; [
    git
    wget
    self.inputs.nvf.packages.${system}.default
    vim
    fastfetch
    yazi
    brave
    obsidian
    bitwarden-desktop
    localsend
  ];
  nix.enable = false;
  fonts.packages = [
    pkgs.nerd-fonts.fira-code
    pkgs.nerd-fonts.fira-mono
    pkgs.nerd-fonts.hack
    pkgs.nerd-fonts.jetbrains-mono
  ];

  nixpkgs.config.allowUnfree = true;

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
      "/Applications/Waterfox.app"
      "/Applications/Ghostty.app"
      "/Applications/Cubase 14.app"
      "System/Applications/System Settings.app"
    ];

    loginwindow.GuestEnabled = false;
  };
}
