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

    environment.systemPackages = with pkgs; [
      attic-client
      tree
      sbctl
      btop
      pciutils
      vim
      self.inputs.nvf.packages.${pkgs.system}.default
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

    services.tailscale = {
      enable = false;
      openFirewall = true;
    };

  };
}
