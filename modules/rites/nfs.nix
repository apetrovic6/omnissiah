{self, ...}: {
  flake.nixosModules.nfs = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption mkIf types mkMerge mapAttrsToList mapAttrs' nameValuePair;
    cfg = config.services.imperium.nfs;
  in {
    options.services.imperium.nfs = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Imperium NFS mount abstraction.";
      };

      hosts = mkOption {
        description = "NFS hosts and their exports.";
        default = {};
        type = types.attrsOf (types.submodule ({name, ...}: {
          options = {
            host = mkOption {
              type = types.str;
              default = name;
              description = "Hostname or IP of the NFS server.";
            };

            exports = mkOption {
              description = "Exported paths on this NFS host.";
              default = {};
              type = types.attrsOf (types.submodule ({name, ...}: {
                options = {
                  remotePath = mkOption {
                    type = types.str;
                    default = name;
                    description = "Remote export path on the NFS server (e.g. /volume1/backup).";
                  };

                  mountPoint = mkOption {
                    type = types.str;
                    description = "Local mount point (e.g. /mnt/nas/backup).";
                  };

                  nfsVersion = mkOption {
                    type = types.enum ["3" "4" "4.1" "4.2"];
                    default = "4.1";
                    description = "NFS protocol version.";
                  };

                  extraOptions = mkOption {
                    type = types.listOf types.str;
                    default = [];
                    description = "Extra NFS mount options to append.";
                  };
                };
              }));
            };
          };
        }));
      };
    };

    config = mkIf (cfg.enable && cfg.hosts != {}) {
      environment.systemPackages = with pkgs; [nfs-utils];

      fileSystems = mkMerge (mapAttrsToList (
          _hostName: hostCfg:
            mapAttrs' (
              _exportKey: exportCfg: let
                options =
                  [
                    "nfsvers=${exportCfg.nfsVersion}"
                    "x-systemd.automount"
                    "noauto"
                    "_netdev"
                    "nofail"
                  ]
                  ++ exportCfg.extraOptions;
              in
                nameValuePair exportCfg.mountPoint {
                  device = "${hostCfg.host}:${exportCfg.remotePath}";
                  fsType = "nfs";
                  inherit options;
                }
            )
            hostCfg.exports
        )
        cfg.hosts);
    };
  };
}
