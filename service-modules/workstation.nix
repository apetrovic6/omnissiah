{
  _class = "clan.service";
  manifest.name = "base";

  roles.default.perInstance.nixosModule = { lib, pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      alacritty
      kitty
      ghostty
      wezterm

      zathura
      gnome.file-roller
      obsidian

      brave
      librewolf-bin
      firefox
      
      vlc

      vesktop
    ];

   sound.enable = true;
  hardware.pulseaudio.enable = false;
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
