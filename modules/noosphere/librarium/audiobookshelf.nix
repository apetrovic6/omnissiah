{ self, ... }:
{
  self.nixosModules.noosphere.audioBookshelf = {config, lib, pkgs, ...}:
let
  inherit (lib) mkIf mkOption mkEnableOption types mkPackageOption;
  cfg = config.services.imperium.audiobookshelf;
in
  {
    options.services.imperium.audiobookshelf = {
      enable = mkEnableOption "Enable Audiobookshelf";

      package = mkPackageOption pkgs "audiobookshelf" {};

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open ports in the firewall for the Audiobookshelf web interface";
      };

      host = mkOption {
        type = types.str;
        default = "0";
        description = "The interface Audiobookshelf binds to.";
      };

      port = mkOption {
        type = types.port;
        description = "The TCP port Audiobookshelf will listen on.";
        default = 8000;
      };

       user = mkOption {
        description = "User account under which Audiobookshelf runs.";
        default = "audiobookshelf";
        type = types.str;
      };

      group = mkOption {
        description = "Group under which Audiobookshelf runs.";
        default = "audiobookshelf";
        type = types.str;
      };
      
      domain = mkOption {
        description = "Domain name under which will app be accessible";
        default = "";
        type = types.str;
      };

    };
  };
}
