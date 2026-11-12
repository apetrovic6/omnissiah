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
    # The FULL nixarchy desktop: nixarchy's own NixOS and home-manager
    # modules, Install menu and all. Replaces magos.nixosModules.omarchy (the
    # package-only port); the two must never be imported together. To go back,
    # revert the commit that swapped them, or boot the previous generation.
    self.inputs.magos.nixosModules.nixarchy
  ];

  magos.nixarchy = {
    enable = true;
    user = "apetrovic";

    # Apps from Omarchy's Install menu, declared here instead of picked there.
    # Ids are nixarchy's data/apps.nix (zen, ghostty, vscode, _1password, ...).
    # The menu's own Install/Apply is not wired to this flake, so use this.
    apps = {
      # zen.enable = true;
    };

    # nixarchy's bundled services: tailscale, syncthing, openssh, boxes,
    # devenv, microvm, open-webui, agent-local.
    services = {
      # syncthing.enable = true;
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
