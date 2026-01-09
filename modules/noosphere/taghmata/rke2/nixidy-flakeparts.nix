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

  globalSsoProvider = lib.attrByPath ["noosphere" "sso" "provider"] "" config;
  globalSsoUrl = lib.attrByPath ["noosphere" "sso" "url"] "" config;
  globalWellKnownUrl = lib.attrByPath ["noosphere" "sso" "wellKnownUrl"] "" config;
in {
  options = {
    perSystem = mkPerSystemOption ({...}: {
      options.noosphere = {
        domain = mkOption {
          type = types.str;
          default = "";
          description = "Base domain used by nixidy modules.";
        };

        sso = {
          provider = mkOption {
            type = types.str;
            default = "";
            description = "Name of the SSO Provider.";
          };

          url = mkOption {
            type = types.str;
            default = "";
            description = "URL/FQDN of the SSO Provider.";
          };

          wellKnownUrl = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Well known URL endpoint";
          };
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
            (
              {lib, ...}:
              # These values go INTO the nixidy module graph
                lib.mkMerge [
                  {
                    noosphere.domain = lib.mkDefault cfg.domain;
                    noosphere.sso.provider = lib.mkDefault cfg.sso.provider;
                    noosphere.sso.wellKnownUrl = lib.mkDefault cfg.sso.wellKnownUrl;
                  }

                  (lib.mkIf (cfg.sso.url != "") {
                    # If explicitly set at flake/perSystem, pass it through.
                    # Plain assignment is fine; it will override mkDefault-derived values.
                    noosphere.sso.url = cfg.sso.url;
                  })
                ]
            )

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
      noosphere.sso.provider = lib.mkDefault globalSsoProvider;
      noosphere.sso.url = lib.mkDefault globalSsoUrl;
      noosphere.sso.wellKnownUrl = lib.mkDefault globalWellKnownUrl;

      legacyPackages.nixidyEnvs.${system} = self.inputs.nixidy.lib.mkEnvs {
        inherit pkgs;

        charts =
          self.inputs.nixhelm.chartsDerivations.${system}
          // {
            deuxfleurs.garage = "${self.inputs.garage}/script/helm/garage";
            lukasdietrich.glance-k8s = "${self.inputs.glance-k8s}/charts/glance-k8s";
            lukasdietrich.glance = "${self.inputs.glance-k8s}/charts/glance-k8s";
            woodpecker-ci.woodpecker = "${self.inputs.woodpecker-ci}/charts/woodpecker";
          };

        envs = lib.mapAttrs mkEnv enabledEnvs;
      };

      packages.nixidy = self.inputs.nixidy.packages.${system}.default;
    };
  };
}
