{
  self,
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      system,
      ...
    }: {
      options.noosphere = {
        domain = mkOption {
          type = types.str;
          default = "";
          description = "Base domain used by nixidy modules.";
        };

        nixidy = {
          repository = mkOption {
            type = types.str;
            description = "Git repo where rendered manifests are pushed to.";
          };

          branch = mkOption {
            type = types.str;
            default = "master";
            description = "Default branch for rendered manifests.";
          };

          rootPath = mkOption {
            type = types.str;
            default = "./manifests/dev";
            description = "Base folder for env rootPath";
            example = "./manifests/dev";
          };
        };

        envs = mkOption {
          type = types.attrsOf (types.submodule ({name, ...}: {
            options = {
              enable = mkOption {
                type = types.bool;
                default = name == "dev";
              };
              branch = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
              rootPath = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Override rootPath for this env.";
              };

              extraModules = mkOption {
                type = types.listOf types.path;
                default = [];
              };
            };
          }));

          default = {
            dev = {};
            prod = {enable = false;};
          };

          description = "Nixidy environments to be generated";
        };
      };
    });
  };

  config = {
    perSystem = {
      config,
      pkgs,
      system,
      ...
    }: let
      cfg = config.noosphere;
      enabledEnvs = lib.filterAttrs (_: e: e.enable) cfg.envs;

      mkEnv = envName: envCfg: let
        branch =
          if envCfg.branch != null
          then envCfg.branch
          else cfg.nixidy.branch;
        rootPath =
          if envCfg != null
          then envCfg.rootPath
          else "${cfg.nixidy.rootPath}/${envName}";
      in {
        modules =
          [
            ../nixidy/modules/noosphere-options.nix

            ({...}: {
              noosphere.domain = cfg.domain;
            })

            ({...}: {
              nixidy.target = {
                repository = cfg.nixidy.repository;
                branch = branch;
                rootPath = rootPath;
              };
            })
          ]
          ++ (
            if builtins.pathExists (../nixidy/env/${envName}.nix)
            then [../nixidy/env/${envName}.nix]
            else []
          )
          ++ envCfg.extraModules;
      };
    in {
      legacyPackages = {
        nixidyEnvs.${system} = self.inputs.nixidy.lib.mkEnvs {
          inherit pkgs;

          charts =
            self.inputs.nixhelm.chartsDerivations.${system}
            // {
              deuxfleurs.garage = "${self.inputs.garage}/script/helm/garage";
            };

          envs = lib.mapAttrs mkEnv enabledEnvs;
        };
      };
      packages.nixidy = self.inputs.nixidy.packages.${system}.default;
    };
  };
}
