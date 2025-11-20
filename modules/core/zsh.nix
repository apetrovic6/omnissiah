{self, ...}: {
  flake.homeModules.zsh = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
   cfg = config.programs.imperium.zsh;

  in {
options.programs.imperium.zsh {
   enable = mkEnableOption "Enable Zsh";
};
    programs.zsh = {
      enable = true;

      config = mkIf cfg.enable {
      autosuggestion.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
};      

    };

  environment.pathsToLink = [
    "/share/zsh"
  ];

    
  };
}
