{lib, ...}:
{
  imports = [
    ./starship.nix
  ];
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "apetrovic";
  home.homeDirectory = "/home/apetrovic";

  stylix = {
    enable = true;
    image = ../../wallpapers/everforest/1.png;
  };


  programs.bash = {
    enable = true;
    initExtra = ''
      fastfetch
      eval "$(starship init bash)"
    '';
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
   home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
   programs.home-manager.enable = true;
}
