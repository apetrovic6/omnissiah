{self, ...}: {
  flake.nixosModules.persistance = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkDefault mkEnableOption types;
    cfg = config.services.imperium.persistance;
  in {
    options.services.imperium.persistance = {
      enable = mkEnableOption "enable persistance";

      volumeGroup = mkOption {
        default = "btrfs_vg";
        description = ''
          Btrfs volume group name
        '';
      };

      user = mkOption {
        default = "username";
        description = ''
          Main user
        '';
      };

      directories = mkOption {
        default = [];
        description = ''
          directories to persist
        '';
      };

      files = mkOption {
        default = [];
        description = ''
          files to persist
        '';
      };

      data.directories = mkOption {
        default = [];
        description = ''
          directories to persist
        '';
      };

      data.files = mkOption {
        default = [];
        description = ''
          files to persist
        '';
      };

      cache.directories = mkOption {
        default = [];
        description = ''
          directories to persist
        '';
      };

      cache.files = mkOption {
        default = [];
        description = ''
          files to persist
        '';
      };
    };
  };
}
