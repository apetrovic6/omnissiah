{self, ...}: {
  flake.nixosModules.steam = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.steam;
  in {
    options.services.imperium.steam = {
      enable = mkEnableOption "Enable Steam";
    };
    config = mkIf cfg.enable {
      programs = {
        gamescope = {
          enable = true;
          capSysNice = true;
        };

        steam = {
          enable = true;
          gamescopeSession.enable = true;
        };
      };
      environment.systemPackages = with pkgs; [mangohud];
    };
  };
}
