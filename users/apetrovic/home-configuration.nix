{
  pkgs,
  self,
  lib,
  config,
  osConfig,
  ...
}: let
  atticToken =
    osConfig.clan.core.vars.generators.attic-pull-token.files.token.path;

  atticSubstituter =
    osConfig.clan.core.vars.generators.attic-pull-token.files.attic-substituter.path;
in {
  imports = [
    self.inputs.magos.homeManagerModules.default
    self.inputs.omnishell.homeManagerModules.default

    ./firefox
  ];

  xdg = {
    enable = true;
  };

  home.packages = with pkgs; [];

  nix = {
    extraOptions = ''
      always-allow-substitutes = true
    '';

    settings = {
      netrc-file = /home/apetrovic/.config/nix/netrc;
      trusted-users = ["root" "apetrovic"];
      trusted-public-keys = [
        "manjo:NYye+6m7jUVm3d9GUoIjXeX55/sz9xnRP/gl8THza6k="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
    };
  };

  programs.bash.initExtra = ''
    export SSH_AUTH_SOCK=/home/apetrovic/.bitwarden-ssh-agent.sock
  '';

  magos.hyprland.hm = {
    input = {
      kbLayouts = ["us" "hr"];
    };
  };

  # programs.noctalia-shell = {
  #   settings = {
  #     bar.backgroundOpacity = 0;
  #     location = {
  #       name = "Zagreb";
  #     };
  #   };
  # };

  magos.hm.stylix = {
    enable = true;
    image = ../../wallpapers/everforest/3.jpg; # optional
    # image = ../../wallpapers/everforest/1.png; # optional
    polarity = "dark";

    targets.firefox.profileNames = ["apetrovic"];
  };

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "apetrovic";
  home.homeDirectory = "/home/apetrovic";

  programs.obsidian.enable = true;

  nixpkgs.config.allowUnfree = true;

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
