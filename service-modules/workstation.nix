{
  _class = "clan.service";
  manifest.name = "workstation";
  manifest.readme = "";

  roles.default.description = "Base packages and services";

  roles.default.perInstance.nixosModule = { self, config, lib, pkgs, ... }: {
    imports = [
      self.inputs.magos.nixosModules.default

      ../modules/core/flatpaks.nix
      ../modules/core/hyprland.nix
      ../modules/core/bluetooth.nix
    ];

    services.magos.hyprland = {
      enable = true;
      nvidia = {
        enable = true;
        modesetting = true;
        powerManagement = true;
      };
    };

    services.magos.bluetooth.enable = true;

    magos.stylix = {
      #enable = true;
              image = ../wallpapers/lofi/2.jpg;
    };

    boot.plymouth = {
      enable = true;
    };


    services.greetd = {
      enable = true;
      settings = {
      default_session = {
        user = "apetrovic";
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland"; # start Hyprland with a TUI login manager
      };
    };
  };


    programs.regreet = {
      enable = true;

      settings = {
        # background.path = config.stylix.image;
        timezone = "Europe/Zagreb";
      };

      # font = lib.mkForce {
      #   package = config.stylix.fonts.monospace.package;
      #   name = config.stylix.fonts.monospace.name;
      #   size = config.stylix.fonts.sizes.desktop;
      # };
    };

    environment.systemPackages = with pkgs; [
      xfce.thunar
      zathura
      file-roller
      obsidian

      brave
      librewolf-bin
      
      vlc

      vesktop

      remmina
      freerdp
    ];

    programs.localsend = {
      enable = true;
    };

    security.rtkit.enable = true;
    services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };
};
}
