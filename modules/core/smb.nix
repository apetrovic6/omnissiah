{self, ...}: {
  flake.nixosModules.smb = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption mkIf types mkMerge mapAttrsToList mapAttrs' nameValuePair;
    cfg = config.services.imperium.smb;
  in {
    options.services.imperium.smb = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Imperium SMB mount abstraction.";
      };

      hosts = mkOption {
        description = "SMB hosts and their shares.";
        default = {};
        type = types.attrsOf (types.submodule ({name, ...}: {
          options = {
            host = mkOption {
              type = types.str;
              default = name;
              description = "Hostname or IP of the SMB server.";
            };

            workgroup = mkOption {
              type = types.str;
              default = "WORKGROUP";
              description = "SMB workgroup / domain.";
            };

            credentialsVarName = mkOption {
              type = types.str;
              default = "smb-${name}-credentials";
              description = "Name of the Clan Vars generator that stores credentials for this host.";
            };

            shares = mkOption {
              description = "Shares on this SMB host.";
              default = {};
              type = types.attrsOf (types.submodule ({name, ...}: {
                options = {
                  shareName = mkOption {
                    type = types.str;
                    default = name;
                    description = "Share name on the SMB server.";
                  };

                  mountPoint = mkOption {
                    type = types.str;
                    description = "Local mount point (e.g. /mnt/nas/games).";
                  };

                  uid = mkOption {
                    type = types.int;
                    default = 1000;
                    description = "UID that should own files.";
                  };

                  gid = mkOption {
                    type = types.int;
                    default = 100;
                    description = "GID that should own files.";
                  };

                  extraOptions = mkOption {
                    type = types.listOf types.str;
                    default = [];
                    description = "Extra CIFS mount options to append.";
                  };
                };
              }));
            };
          };
        }));
      };
    };

    config = mkIf (cfg.enable && cfg.hosts != {}) {
      environment.systemPackages = with pkgs; [cifs-utils];

      # One Clan Vars generator per SMB host for credentials
      clan.core.vars.generators = mapAttrs' (
        hostName: hostCfg: let
          genName = hostCfg.credentialsVarName;
        in
          nameValuePair genName {
            share = true;
            runtimeInputs = [pkgs.coreutils];
            script = ''
              set -eu
              {
                printf "username=%s\n" "$(cat "$prompts/username")"
                printf "password=%s\n" "$(cat "$prompts/password")"
                printf "domain=%s\n"   "$(cat "$prompts/domain")"
              } > "$out/credentials"
            '';
            files.credentials = {
              secret = true;
              owner = "root";
              group = "root";
              mode = "0400";
            };
            prompts.username = {
              description = "SMB username for ${hostName}";
              type = "line";
              persist = true;
              display.label = "SMB username (${hostName})";
            };
            prompts.password = {
              description = "SMB password for ${hostName}";
              type = "hidden";
              persist = true;
              display.label = "SMB password (${hostName})";
            };
            prompts.domain = {
              description = "SMB workgroup / domain for ${hostName}";
              type = "line";
              persist = true;
              display.label = "SMB workgroup (${hostName})";
              default = hostCfg.workgroup;
            };
          }
      )
      cfg.hosts;

      # One fileSystems entry per share on each host
      fileSystems = mkMerge (mapAttrsToList (
          hostName: hostCfg: let
            credsPath =
              config.clan.core.vars.generators.${hostCfg.credentialsVarName}.files.credentials.path;
          in
            mapAttrs' (
              shareKey: shareCfg: let
                options =
                  [
                    "credentials=${credsPath}"
                    "uid=${builtins.toString shareCfg.uid}"
                    "gid=${builtins.toString shareCfg.gid}"
                    "vers=3.1.1"
                    "x-systemd.automount"
                    "noauto"
                    "_netdev"
                    "nofail"
                  ]
                  ++ shareCfg.extraOptions;
              in
                nameValuePair shareCfg.mountPoint {
                  device = "//${hostCfg.host}/${shareCfg.shareName}";
                  fsType = "cifs";
                  inherit options;
                }
            )
            hostCfg.shares
        )
        cfg.hosts);
    };
  };
}
