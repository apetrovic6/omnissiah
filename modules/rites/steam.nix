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
          args = [
            "--steam"
            "--expose-wayland"
            "--rt"
            "--force-grab-cursor"
            "--grab"
            "--fullscreen"
          ];
        };

        # gamemode.enable = true;

        steam = {
          enable = true;
          gamescopeSession.enable = true;
          extraCompatPackages = with pkgs; [
            proton-ge-bin
          ];

          package = pkgs.steam.override {
            extraPkgs = pkgs':
              with pkgs'; [
                xorg.libXcursor
                xorg.libXi
                xorg.libXinerama
                xorg.libXScrnSaver
                libpng
                libpulseaudio
                libvorbis
                stdenv.cc.cc.lib # Provides libstdc++.so.6
                libkrb5
                keyutils
                # Add other libraries as needed
              ];
          };

          extraPackages = with pkgs; [
            SDL2
            gamescope
            er-patcher
            gamescope-wsi
          ];

          protontricks.enable = true;
        };
      };
      environment.systemPackages = with pkgs; [mangohud];
    };
  };
}
