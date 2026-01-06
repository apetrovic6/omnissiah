{
  self,
  lib,
  flake-parts-lib,
  config,
  ...
}: let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;

  # Global domain from flake-level config (set in flake.nix as noosphere.domain = "…")
  globalDomain = config.noosphere.domain;
in {
  options = {
    perSystem = mkPerSystemOption ({
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
          if envCfg.rootPath != null
          then envCfg.rootPath
          else "${cfg.nixidy.rootPath}/${envName}";
      in {
        modules =
          [
            ../nixidy/_modules/noosphere-options.nix

            ({...}: {
              # This value goes INTO the nixidy module graph
              noosphere.domain = cfg.domain;
            })

            ({...}: {
              nixidy.target = {
                repository = cfg.nixidy.repository;
                inherit branch rootPath;
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
      # Default per-system domain from the flake-level domain
      noosphere.domain = lib.mkDefault globalDomain;

      legacyPackages.nixidyEnvs.${system} = self.inputs.nixidy.lib.mkEnvs {
        inherit pkgs;

        charts =
          self.inputs.nixhelm.chartsDerivations.${system}
          // {
            deuxfleurs.garage = "${self.inputs.garage}/script/helm/garage";
            lukasdietrich.glance-k8s = "${self.inputs.glance-k8s}/charts/glance-k8s";
            lukasdietrich.glance = "${self.inputs.glance-k8s}/charts/glance-k8s";
          };

        envs = lib.mapAttrs mkEnv enabledEnvs;
      };

      packages.nixidy = self.inputs.nixidy.packages.${system}.default;
    };
  };
}
