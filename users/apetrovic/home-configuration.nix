{
  pkgs,
  self,
  lib,
  ...
}: {
  imports = [
    self.inputs.magos.homeManagerModules.default
    ./firefox
  ];

  nix = {
    extraOptions = ''
      !include /home/apetrovic/.secrets/attic-pull
    '';
    settings = {
      substituters = [
        "https://attic.manjaca.xyz/manjo"
      ];

      trusted-substituters = [
        "https://attic.manjaca.xyz/manjo"
      ];
      trusted-public-keys = [
        "manjo:NYye+6m7jUVm3d9GUoIjXeX55/sz9xnRP/gl8THza6k="
      ];
    };
  };

  xdg = {
    enable = true;
  };

  home.packages = with pkgs; [
    cowsay
  ];

  magos.hm.stylix = {
    enable = true; # plain false overrides mkDefault true
    image = ../../wallpapers/lofi/17.png; # optional
    polarity = "dark";

    targets.firefox.profileNames = ["apetrovic"];
  };

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "apetrovic";
  home.homeDirectory = "/home/apetrovic";

  programs.obsidian.enable = true;

  nixpkgs.config.allowUnfree = true;

  programs.cava = {
    enable = true;
  };

  programs.cavalier = {
    enable = true;
  };

  programs.eza = {
    enable = true;
    git = true;
  };

  programs.bat = {
    enable = true;
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    settings.user = {
      name = "apetrovic";
      email = "petrovicante6@gmail.com";
    };
  };

  programs.btop.enable = true;

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
