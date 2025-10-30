{
  _class = "clan.service";
  manifest.name = "workstation";

  roles.default.description = "Base packages and services";

  roles.default.perInstance.nixosModule = { lib, pkgs, ... }: {
    imports = [
      ../modules/core/flatpaks.nix
      ../modules/core/stylix.nix
    ];

    environment.systemPackages = with pkgs; [
      alacritty
      kitty
      ghostty
      wezterm

      zathura
      file-roller
      obsidian

      brave
      librewolf-bin
      firefox
      
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
