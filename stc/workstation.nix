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
      self.inputs.magos.nixosModules.pi
      self.inputs.magos.nixosModules.omp
      # self.nixosModules.flatpak
      self.nixosModules.bluetooth
      self.nixosModules.virtualisation
    ];

    # ── Pi / OMP: declarative API key injection via sops ──────────
    # The pi-api-keys clan vars generator (in modules/vars) creates and
    # sops-encrypts the key. Enable the agents here once the secret is
    # generated:
    #   clan vars generate --generator pi-api-keys <machine>
    #
    magos.agents.pi = {
      enable = true;
      apiKeys.qwen = config.clan.core.vars.generators.pi-api-keys.files."qwen-api-key".path;
      # apiKeys.anthropic = config.clan.core.vars.generators.pi-api-keys.files."anthropic-api-key".path;
      # apiKeys.openai    = config.clan.core.vars.generators.pi-api-keys.files."openai-api-key".path;

      # Hide Bedrock/Vertex from pi's /model picker. pi treats them as
      # authenticated purely from ambient env vars (AWS_PROFILE alone is
      # enough), and `enabledModels` cannot suppress that — it only scopes
      # startup selection and Ctrl+P cycling.
      #
      # CAVEAT: this unsets AWS_PROFILE / AWS_ACCESS_KEY_ID / etc. for pi's
      # whole process tree, so pi's bash tool — and terraform / aws / kubectl
      # run through it — loses those credentials. Drop "amazon-bedrock" from
      # this list if you drive AWS from inside pi.
      blockAmbientCredentials = ["amazon-bedrock"];
    };
    magos.agents.omp.enable = true; # piggybacks on pi's apiKeys

    nixpkgs.overlays = [
      self.overlays.pangolin-cli
      self.overlays.helix
      self.overlays.herdr
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

    systemd.user.services.niri.serviceConfig.CPUWeight = 100;

    services.imperium.flatpak.enable = true;

    services.imperium.virtualisation.podman = {
      enable = true;
      enableDockerSocket = true;
      enableDockerCompat = true;
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

    # ── Printing and scanning against servitor ───────────────────
    # servitor (192.168.1.13) shares an HP LaserJet MFP M28-M31 over CUPS and
    # its flatbed over saned. The two are found in different ways: the printer
    # really is discovered over DNS-SD, the scanner has to be pinned. See
    # netConf below for why.
    services.printing = {
      enable = true;

      # On servitor this is deliberately off; here it is the whole point.
      # cups-browsed imports *remote* DNS-SD-advertised queues and turns them
      # into local ones, which is the direction a client wants. Without it,
      # only applications that do their own avahi browsing (the GTK print
      # dialog) see the printer, and `lp`/`lpr` from a shell do not.
      browsed.enable = true;
    };

    hardware.sane = {
      enable = true;

      # saned has to be named explicitly: it never shows up over mDNS.
      #
      # The binary does link avahi and can register _sane-port._tcp, but the
      # NixOS module runs it from a socket unit with Accept=yes, i.e. one
      # short-lived process per connection, and a per-connection process
      # never registers a service. Confirmed on servitor: `avahi-browse -rtp
      # _sane-port._tcp` returns nothing while _ipp._tcp lists the printer.
      netConf = "192.168.1.13";
    };

    services.avahi = {
      enable = true;

      # cups-browsed browses _ipp._tcp through avahi to find servitor's queue.
      # Scanning does not depend on this -- see netConf above.
      nssmdns4 = true;

      # Lets servitor.local resolve, which is also what the printer's DNS-SD
      # record points its adminurl at.
      openFirewall = true; # 5353/udp
    };

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

    # Workaround for stylix 5b298f7, which renamed ImageMagick `convert` to
    # `magick` in modules/plymouth/nixos.nix without reordering the arguments.
    # IM7's parser needs an image on the stack before an image operator, and
    # `-border 42%` is still emitted ahead of the logo, so the theme fails to
    # build with "no images found for operation `-border'". The border is only
    # emitted when logoAnimated is set, so turning it off sidesteps it; we lose
    # the spinner but keep the themed splash. Revert once stylix is fixed.
    stylix.targets.plymouth.logoAnimated = false;

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          user = "apetrovic";
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        };
      };
    };

    services.displayManager.regreet = {
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
      libreoffice

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
      kubectx
      kubectl-cnpg

      signal-desktop

      claude-code
      claude-monitor

      exercism

      obs-studio
      xwayland

      (self.inputs.dagger-cli.packages.${system}.dagger)

      herdr
      (self.inputs.magos.packages.${system}.opencode)
      python3Packages.huggingface-hub

      # neomutt
      proton-vpn-cli
      pangolin-cli
      element-desktop

      helix

      google-chrome
      chromium
      slack

      quickemu
      evtest
      librepods
      alacritty
      nfs-utils
      (buildIdeWithPlugins pkgs "idea" commonPlugins)
      (buildIdeWithPlugins pkgs "rust-rover" commonPlugins)
      (buildIdeWithPlugins pkgs "goland" commonPlugins)
      (buildIdeWithPlugins pkgs "datagrip" commonPlugins)
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

    services.tailscale = {
      enable = true;
      openFirewall = true;
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
