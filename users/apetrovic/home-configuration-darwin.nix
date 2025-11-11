{
  pkgs,
  self,
  lib,
  ...
}: {
  imports = [
    ./firefox
  ];

  home.packages = [
    pkgs.cowsay
  ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "apetrovic";
  home.homeDirectory = lib.mkForce "/Users/apetrovic";

  #programs.obsidian.enable = true;

  # nixpkgs.config.allowUnfree = true;
  #
  # programs.cava = {
  #   enable = true;
  # };
  #
  programs.eza = {
    enable = true;
    git = true;
  };

  programs.bat = {
    enable = true;
  };

  # programs.git = {
  #   enable = true;
  #   lfs.enable = true;
  #   settings.user = {
  #     name = "apetrovic";
  #     email = "petrovicante6@gmail.com";
  #   };
  # };
  #
  # programs.btop.enable = true;
  #
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.lazygit = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    initContent = ''
      fastfetch
      eval "$(starship init zsh)"
      export SSH_AUTH_SOCK=/Users/apetrovic/.bitwarden-ssh-agent.sock
    '';
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
