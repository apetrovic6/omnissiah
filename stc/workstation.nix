{...}: {
  _class = "clan.service";
  manifest.name = "workstation";
  manifest.readme = "";

  roles.default.description = "Base packages and services";

  roles.default.perInstance.nixosModule = {
    self,
    config,
    pkgs,
    lib,
    ...
  }: {
    imports = [
      self.nixosModules.flatpak
      self.inputs.magos.nixosModules.desktop
      # self.nixosModules.flatpak
      self.nixosModules.bluetooth
      self.nixosModules.virtualisation
    ];

    nixpkgs.overlays = [
      self.overlays.pangolin-cli
      self.overlays.openldap
    ];
    networking.nameservers = ["192.168.1.105"];
    # Prevent NetworkManager from pushing DHCP-provided DNS to systemd-resolved,
    # which would override Technitium and cause intermittent split-horizon failures.
    networking.networkmanager.dns = lib.mkForce "none";
    # Remove compiled-in fallback DNS servers so only Technitium is used.
    services.resolved.fallbackDns = [];

    services.gnome.gnome-keyring.enable = true;
    security.pam.services.login.enableGnomeKeyring = true;
    services.passSecretService.enable = true;

    services.xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    services.imperium.flatpak.enable = true;

    services.imperium.virtualisation.podman = {
      enable = true;
      enableDockerSocket = true;
    };

    hardware.keyboard.qmk.enable = true;

    system.autoUpgrade = {
      enable = true;
      dates = "weekly";
    };

    programs.appimage.enable = true;
    programs.appimage.binfmt = true;

    # magos.core.hyprland = {
    #   enable = true;
    #   xwayland = true;
    #   nvidia = {
    #     enable = true;
    #     modesetting = true;
    #     powerManagement = true;
    #   };
    # };

    networking.firewall = {
      allowedTCPPorts = [
        53317 # LocalSend
      ];

      allowedUDPPorts = [
        53317 # LocalSend
      ];
    };

    services.imperium.bluetooth.enable = true;

    magos.stylix = {
      enable = true;
      image = ../wallpapers/everforest/1.png;
      base16Scheme = "everforest-dark-soft";
      # base16Scheme = "nord";
    };

    boot.plymouth = {
      enable = true;
    };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          user = "apetrovic";
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        };
      };
    };

    programs.regreet = {
      enable = true;

      settings = {
        background.path = config.stylix.image;
        timezone = "Europe/Zagreb";
      };

      # font = lib.mkForce {
      #   package = config.stylix.fonts.monospace.package;
      #   name = config.stylix.fonts.monospace.name;
      #   size = config.stylix.fonts.sizes.desktop;
      # };
    };

    environment.systemPackages = with pkgs; let
      inherit (self.inputs.nix-jetbrains-plugins.lib) buildIdeWithPlugins;

      commonPlugins = [
        "IdeaVIM"
      ];

      intellijPlugins = [
        "com.jetbrains.kmm"
      ];
    in [
      thunar
      zathura
      file-roller
      obsidian

      bluetuith
      brave
      librewolf

      vlc

      vesktop

      freerdp

      plex-desktop
      plex-htpc
      plexamp
      bitwarden-desktop

      wiremix

      virt-manager
      qemu

      k9s
      kubectl
      kubectl-cnpg

      signal-desktop

      claude-code
      claude-monitor

      exercism

      obs-studio
      xwayland

      (self.inputs.dagger-cli.packages.${system}.dagger)

      neomutt
      proton-vpn-cli
      pangolin-cli
      element-desktop

      quickemu
      evtest
      librepods
      alacritty
      nfs-utils
      (buildIdeWithPlugins pkgs "idea" commonPlugins)
      (buildIdeWithPlugins pkgs "rust-rover" commonPlugins)
      (buildIdeWithPlugins pkgs "goland" commonPlugins)
      jetbrains-toolbox
    ];

    services.spice-vdagentd.enable = true;

    services.protonmail-bridge = {
      enable = true;
      path = with pkgs; [pass gnome-keyring];
    };

    programs.localsend = {
      enable = true;
    };

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
    };
  };
}
