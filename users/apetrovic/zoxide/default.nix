{ self, ... }: {
  flake.homeModules.zoxide = { config, lib, pkgs, ... }:
  let
    inherit (lib) mkIf mkOption mkEnableOption mkDefault types;

    zshOn  = config.programs.imperium.zsh.enable  or false;
    bashOn = config.programs.imperium.bash.enable or false;
    fishOn = config.programs.imperium.fish.enable or false;

    cfg = config.programs.imperium.zoxide;
  in {
    options.programs.imperium.zoxide = {
      enable = mkEnableOption "Enable zoxide via Imperium.";

      enableZshIntegration = mkOption {
        type = types.bool;
        default = zshOn;
        description = "Enable Zsh integration (defaults to true if Imperium Zsh is enabled).";
      };

      enableBashIntegration = mkOption {
        type = types.bool;
        default = bashOn;
        description = "Enable Bash integration (defaults to true if Imperium Bash is enabled).";
      };

      enableFishIntegration = mkOption {
        type = types.bool;
        default = fishOn;
        description = "Enable Fish integration (defaults to true if Imperium Fish is enabled).";
      };

      command = mkOption {
        type = types.str;
        default = "z";
        description = "Command name used to invoke zoxide.";
      };

      extraCommands = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "--hook" "pwd" "--no-cmd" ];
        description = "Extra flags for zoxide init.";
      };
    };

    config = mkIf cfg.enable {
      programs.zoxide = {
        enable = true;

        enableBashIntegration = mkDefault cfg.enableBashIntegration;
        enableZshIntegration  = mkDefault cfg.enableZshIntegration;
        enableFishIntegration = mkDefault cfg.enableFishIntegration;

        options = [ "--cmd" cfg.command ] ++ cfg.extraCommands;
      };
    };
  };
}

