{config, ...}: {
  _class = "clan.service";
  manifest.name = "base";
  manifest.readme = "";

  roles.default.description = "Some basic tools and settings that are needed everywhere";

  roles.default.perInstance.nixosModule = {
    self,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      self.inputs.nix-index-database.nixosModules.default
    ];

    nixpkgs.overlays = [
      self.overlays.go125-shim
    ];

    environment.systemPackages = with pkgs; [
      attic-client
      tree
      sbctl
      btop
      pciutils
      vim
      wget
      git
      fastfetch
      yazi
      killall
      (
        pkgs.writeShellApplication {
          name = "ns";
          runtimeInputs = with pkgs; [
            fzf
            nix-search-tv
          ];
          text = builtins.readFile "${pkgs.nix-search-tv.src}/nixpkgs.sh";
        }
      )
    ];

    services.openssh.settings.MaxAuthTries = 10;

    programs.nix-index-database.comma.enable = true;
    # Firmware updates (UEFI / TB / docks, etc.)
    services.fwupd.enable = true;

    nix = {
      gc = {
        automatic = true;
        dates = "daily";
        options = "--delete-older-than 10d";
      };
      settings = {
        trusted-users = ["apetrovic"];
        auto-optimise-store = true;

        # cache.nixos.org is deliberately absent: nixos/modules/config/nix.nix
        # appends it (and its key) unconditionally, and these are list options
        # whose definitions concatenate rather than override. Listing it here
        # too would just make Nix query the same cache twice on every miss.
        substituters = ["https://ncps.noosphere.uk"];
        trusted-public-keys = [
          (builtins.readFile ../vars/shared/ncps-signing-key/ncps-signing-key.pub/value)
        ];
      };
    };

    networking.networkmanager.enable = true;

    time.timeZone = "Europe/Zagreb";
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "hr_HR.UTF-8";
      LC_IDENTIFICATION = "hr_HR.UTF-8";
      LC_MEASUREMENT = "hr_HR.UTF-8";
      LC_MONETARY = "hr_HR.UTF-8";
      LC_NAME = "hr_HR.UTF-8";
      LC_NUMERIC = "hr_HR.UTF-8";
      LC_PAPER = "hr_HR.UTF-8";
      LC_TELEPHONE = "hr_HR.UTF-8";
      LC_TIME = "hr_HR.UTF-8";
    };

    fonts = {
      packages = with pkgs.nerd-fonts; [
        fira-code
        fira-mono

        jetbrains-mono
      ];
    };

    programs.dconf = {
      enable = true;
    };

    services.xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };
}
