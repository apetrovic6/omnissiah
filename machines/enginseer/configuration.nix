{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  diskId = "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092";
in {
  imports = [
    self.inputs.nix-flatpak.nixosModules.nix-flatpak
    self.inputs.nixos-hardware.nixosModules.asus-zephyrus-gu605my
    self.nixosModules.impermanence
    self.nixosModules.zram
    self.nixosModules.lanzaboote
    self.nixosModules.vars
    self.nixosModules.smb
    # The Omarchy desktop: nixarchy's PACKAGE, none of its modules. Lives in
    # magos (modules/features/omarchy.nix) alongside niri, so phalanx can take
    # the same session with one import. Options under `magos.omarchy`.
    #
    # To roll back, drop this import and the magos.omarchy block below -- but
    # the previous generation also stays bootable, which is the faster revert
    # if the session does not come up.
    self.inputs.magos.nixosModules.omarchy
  ];

  # First real test of modules/omarchy/default.nix. Verified so far by build and
  # by path resolution, NOT by logging in: the QuickShell bar, theme switching
  # and the portals are still unproven.
  #
  # Deliberately not ported from nixarchy, so expect these to be absent:
  #   - the ~/.config seed, so foot/btop/starship/tmux stay unthemed and
  #     ~/.config/hypr/*.lua is not created (the store copies answer instead)
  #   - omarchy-{sleep-lock,crash-watch,recover-internal-monitor,fcitx5} and
  #     bt-agent user units
  #   - gpu-screen-recorder's setcap wrapper, so screen RECORDING will fail
  #     (screenshots go through grim/satty and are fine)
  #   - nix-ld
  magos.omarchy = {
    enable = true;

    # Matched to this fleet's stylix scheme (everforest-dark-soft, see
    # stc/workstation.nix) so the Omarchy desktop and everything stylix themes
    # agree. Applied on first login only, by the session launcher before
    # Hyprland starts; switching from the menu afterwards sticks.
    defaultTheme = "everforest";

    # Omarchy's own foot, which already rides along in the package's
    # passthru.runtimeDeps -- `package = null` is what keeps it there, because a
    # non-null value gets evicted from that list by pname so the named build can
    # replace it rather than collide with it over bin/foot.
    #
    # So this installs no terminal of its own. desktopId is still needed: it is a
    # separate mechanism (/etc/xdg/xdg-terminals.list) and without it
    # xdg-terminal-exec scans desktop entries, which is how SUPER+RETURN opened
    # alacritty -- stc/workstation.nix installs that too.
    #
    # CAVEAT, and the tradeoff being reverted here: this foot comes up on foot's
    # OWN defaults, not Omarchy's. Omarchy's settings live at
    # $OMARCHY_PATH/config/foot/foot.ini (JetBrainsMono 9, 14x14 pad, 10k
    # scrollback, its key-bindings) and that file is what `include=`s the themed
    # ~/.local/state/omarchy/current/theme/foot.ini which omarchy-theme-set
    # renders -- but foot reads only ~/.config/foot/foot.ini, and copying it
    # there is nixarchy's home-manager seed, which this module does not use.
    # magos's build carried the stylix palette compiled in instead, which is why
    # it was themed without any of this.
    #
    # Partial consolation: omarchy-theme-set-foot retints ALREADY-RUNNING foot
    # windows over OSC, so a theme switch from the menu recolors open terminals.
    # New windows still start from the defaults. Fixable without a seed by
    # pointing the desktop entry at `foot -c ${OMARCHY_PATH}/config/foot/foot.ini`
    # (the include inside it is a $HOME path, so theming would then follow).
    terminal = {
      package = null;
      desktopId = "foot.desktop";
    };

    # Omarchy shell plugins. The attribute name is only the directory they
    # land in; the plugin id, its kinds and its bar section come from each
    # manifest.json. A plugin is enabled by being listed -- nothing is written
    # to ~/.config/omarchy.
    #
    # Installing a plugin does not install what it drives. Where a backend is
    # missing the widget loads and the menu opens; it is the actions inside it
    # that fail, so these are inert rather than broken until the backend is
    # there.
    plugins = {
      # herdr sessions and the agents in them. herdr itself comes from
      # stc/workstation.nix.
      herdr = {
        binding = "SUPER + ALT + H";
      };

      # Containers. Drives podman, which services.imperium.virtualisation
      # already enables on this machine.
      podman = {
        # Upstream suggests no chord for this one; SUPER+ALT+D is free in
        # Omarchy 4.0.4 and sits with the other SUPER+ALT plugin menus.
        binding = "SUPER + ALT + D";
      };

      # Browse and install further plugins from the registry. Note anything
      # installed through it lands in ~/.config/omarchy/plugins as a normal
      # third-party plugin -- outside this module, and surviving a rebuild
      # because nothing here manages that directory.
      plugin-browser = {
        binding = "SUPER + ALT + U"; # upstream's own suggestion
      };

      # Lofi radio. lofi-mpris does an unguarded `import gi`, so every helper
      # is pointed at a python carrying PyGObject rather than the bare
      # python3 that `env` would otherwise find.
      lofi-focus = {
        postInstall = let
          py = pkgs.python3.withPackages (ps: [ps.pygobject3]);
        in ''
          for f in $out/lofi-player $out/lofi-ipc $out/lofi-mpris $out/lofi-feed; do
            substituteInPlace "$f" \
              --replace-fail '#!/usr/bin/env python3' '#!${py}/bin/python3'
          done
        '';
      };

      # Windows VM control. INERT until libvirt is set up: it shells out to
      # virsh, which this machine does not have (virtualisation.libvirtd is
      # off, and there is no Windows image). The menu opens; its actions fail.
      winvm = {
        # Menu-only -- no bar widget -- so without a chord there is no way to
        # open it at all. Upstream suggests none; SUPER+ALT+W is free.
        binding = "SUPER + ALT + W";
      };

      # MicroVMs. INERT for the same reason: it drives the `microvm` command
      # from microvm.nix, which this repo deliberately does not import -- that
      # module layer is exactly what this desktop module exists to avoid.
      microvm = {
        binding = "SUPER + ALT + V"; # upstream's own suggestion
      };
    };

    # Everforest wallpaper from this repo, matching the stylix image in
    # stc/workstation.nix, instead of the logo art the theme ships.
    wallpaper = ../../wallpapers/everforest/1.png;

    # Omarchroma: live retinting on theme switch, on top of omarchy-theme-set
    # (which keeps selecting themes) and stylix (which keeps declaring them).
    # Unlike the rest of this module it writes to $HOME through home-manager
    # -- hooks, shell integration, and its own bar plugin, which it installs
    # itself rather than through magos.omarchy.plugins.
    themeEngine = {
      enable = true;
      user = "apetrovic";
    };

    # Four fingers across the touchpad to move between workspaces. Omarchy
    # ships this commented out at three fingers; four leaves the three-finger
    # swipe free for whatever the desktop or apps want.
    gestures = [
      {
        fingers = 4;
        direction = "horizontal";
        action = "workspace";
      }
    ];

    # Proves the declarative path end to end. SUPER+SHIFT+B is an Omarchy
    # default (Browser); unbinding it is visible immediately if bindings work.
    bindings = {
      unbind = ["SUPER + SHIFT + B"];
      bind."SUPER + SHIFT + RETURN" = {
        description = "Terminal (magos)";
        command = "foot";
      };
    };
  };
  # Intel + NVIDIA. Bus IDs read from sysfs and converted to decimal.
  hardware.nvidia.prime = {
    offload.enable = true;
    offload.enableOffloadCmd = true; # gives you `nvidia-offload <cmd>`
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
  # Or sync mode instead -- dGPU drives everything: best performance,
  # worst battery. The two are mutually exclusive; pick one.
  #   hardware.nvidia.prime.sync.enable = true;
  hardware.nvidia.open = true;
  # and in hosts/<name>/nixarchy-hardware.nix:
  #   inputs.nixos-hardware.nixosModules.common-gpu-nvidia

  # nix = {
  #   extraOptions = ''
  #     !include ${config.clan.core.vars.generators.attic-pull-token.files.token.path}
  #     netrc-file = /home/apetrovic/.config/nix/netrc
  #   '';

  #   settings = {
  #     trusted-public-keys = [
  #       "manjo:NYye+6m7jUVm3d9GUoIjXeX55/sz9xnRP/gl8THza6k="
  #     ];
  #   };
  # };
  #

  nixpkgs = {
    overlays = [
      # self.overlays.librewolf
    ];
    config = {
      allowUnfree = true;
      permittedInsecurePackages = ["electron-39.8.10"];
      microsoftVisualStudioLicenseAccepted = true; # PipeASIO (Rocksmith)
    };
  };

  # magos.core.hyprland.monitor = ",2560x1600@240,auto,1.33";
  services.imperium.smb.enable = true;

  services.imperium.smb.hosts.manjaca = {
    host = "192.168.1.61";
    credentialsVarName = "manjaca-nas-credentials";

    shares.games = {
      shareName = "games";
      mountPoint = "/mnt/nas/games";
    };

    shares."3DPrinting" = {
      shareName = "3DPrinting";
      mountPoint = "/mnt/nas/3dprinting";
    };

    shares.home = {
      shareName = "home";
      mountPoint = "/mnt/nas/home";
    };

    shares.data = {
      mountPoint = "/mnt/nas/data";
    };

    shares.uevault = {
      shareName = "UE_VAULT";
      mountPoint = "/mnt/nas/ue_vault";
    };

    shares.docker = {
      mountPoint = "/mnt/nas/ue_vault";
    };
  };

  services.imperium.lanzaboote.enable = true;
  services.imperium.zram.enable = true;

  hardware.nvidia.powerManagement.enable = true;

  services.imperium.impermanence = {
    enable = true;
  };

  users.mutableUsers = false;
  services.dbus.enable = true;
  security.polkit.enable = true;

  # systemd Stage 1: if enabled, it handles unlocking of LUKS-encrypted volumes during boot.
  boot.initrd.luks.devices = {
    cryptroot = {
      device = "/dev/disk/by-partlabel/luks";
      allowDiscards = true;
    };
  };

  # This complements using zram, putting /tmp on RAM
  boot = {
    tmp = {
      useTmpfs = true;
      tmpfsSize = "50%";
    };
  };

  # Enable autoScrub for btrfs
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = ["/"];
  };

  boot.loader = {
    efi.canTouchEfiVariables = false;
    grub.devices = [
      "/dev/disk/by-id/nvme-WD_PC_SN560_SDDPNQE-1T00-1102_23461C801092"
    ];
  };

  # ── DNS: Technitium first, Quad9 behind it ───────────────────────────────
  # This machine only. stc/workstation.nix pins Technitium alone, which is
  # right for a desktop that never leaves the LAN; this is a laptop, and with
  # a single unreachable nameserver it loses DNS entirely on any other
  # network.
  #
  # A local dnsmasq does the splitting, rather than listing Technitium and
  # Quad9 as two peer nameservers.
  #
  # Two peers does not work: systemd-resolved keeps ONE active server at a
  # time (resolvectl calls it "Current DNS Server") and only ever rotates
  # *away* from it on failure, never back. One transient .105 timeout -- wifi
  # resuming, boot ordering, roaming off and back -- parks the machine on
  # Quad9 until resolved is restarted, and Quad9 answers the internal zones
  # with their public Pangolin address (152.53.34.16) instead of the LAN one.
  # Observed here: .105 pingable and answering dig directly, while
  # `resolvectl query forge.ugalabugala.org` still returned 152.53.34.16.
  # `resolvectl reset-server-features` does not clear it (that only resets
  # feature probing); only `systemctl restart systemd-resolved` does.
  #
  # Routing by domain removes the choice entirely: the internal zones can only
  # ever go to Technitium, everything else only ever to Quad9. systemd-resolved
  # cannot express this on its own -- global DNS= is a flat list with no
  # per-server domain routing.
  #
  # Off the home LAN the internal zones simply fail to resolve (Technitium is
  # unreachable) while everything public still works, which is the intended
  # behaviour for a laptop.
  services.dnsmasq = {
    enable = true;

    # The module would otherwise register 127.0.0.1 through resolvconf and
    # fight systemd-resolved over /etc/resolv.conf. resolved stays the stub
    # resolver on 127.0.0.53; it is pointed at dnsmasq via networking.nameservers
    # below.
    resolveLocalQueries = false;

    settings = {
      # resolved already owns 127.0.0.53:53 and 127.0.0.54:53, so bind the
      # plain loopback address only. Without bind-interfaces dnsmasq takes
      # 0.0.0.0:53 and collides with it.
      listen-address = "127.0.0.1";
      bind-interfaces = true;

      # Critical: /etc/resolv.conf points at resolved's stub, so reading it
      # would make dnsmasq forward back into resolved and loop.
      no-resolv = true;

      # First match wins, bare address last as the default.
      server = [
        "/ugalabugala.org/192.168.1.105"
        "/noosphere.uk/192.168.1.105"
        "/keksic.xyz/192.168.1.105"
        "9.9.9.9"
      ];

      # Technitium serves no 1.168.192.in-addr.arpa zone, so reverse lookups of
      # LAN addresses would otherwise be forwarded to Quad9. Answer them
      # NXDOMAIN locally instead of leaking the internal addressing.
      bogus-priv = true;

      cache-size = 1000;
    };
  };

  # Point resolved at dnsmasq. One upstream, so there is no server selection
  # left for resolved to get stuck on -- the routing happens a hop later.
  #
  # mkForce rather than appending: networking.nameservers is a list option, so
  # without it this merges with workstation.nix's ["192.168.1.105"] entry and
  # resolved would go back to picking between two servers.
  networking.nameservers = lib.mkForce ["127.0.0.1"];

  # Without this the nameservers above are quietly overridden on wifi.
  #
  # workstation.nix sets networkmanager.dns = "none", but that key only stops
  # NM writing /etc/resolv.conf. Pushing DNS into systemd-resolved over D-Bus
  # is governed by a *separate* key, main.systemd-resolved, which defaults to
  # true -- so NM keeps registering the DHCP server as a per-link resolver.
  # Observed on this machine: `resolvectl` showed wlo1 with DNS 192.168.1.1
  # and "Default Route: yes" winning over the global 192.168.1.105, while
  # NetworkManager logged `dns-sd-resolved[...]: send-updates SetLinkDomains`.
  networking.networkmanager.settings.main.systemd-resolved = false;
}
