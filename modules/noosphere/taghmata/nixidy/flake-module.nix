# Nixidy Flake-Parts Module
#
# This module provides integration between flake-parts and nixidy for
# Kubernetes manifest generation. It consolidates:
# - perSystem.noosphere.nixidy options
# - CRD package generation
# - gen-crd app generation
# - nixidy environment configuration
#
# Usage in flake.nix:
#   perSystem.noosphere.nixidy = {
#     repository = "https://github.com/user/repo.git";
#     branch = "master";
#
#     crds.definitions = {
#       cert-manager.chart = nixhelm.chartsDerivations.${system}.jetstack.cert-manager;
#       # ...
#     };
#
#     envs.prod = {
#       enable = true;
#       module = ./path/to/prod.nix;
#     };
#   };
{
  self,
  lib,
  flake-parts-lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkEnableOption types mkDefault;
  inherit (flake-parts-lib) mkPerSystemOption;

  # Read global noosphere options (defined in kube-secrets/config/default.nix)
  global = config.noosphere;

  # Path to the _generated directory (relative to this file)
  generatedDirPath = ./_generated;

  # CRD definition submodule
  crdSubmodule = types.submodule ({name, ...}: {
    options = {
      chart = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          Helm chart package for CRD generation.
          Use this for CRDs that come from Helm charts.
        '';
        example = "nixhelm.chartsDerivations.\${system}.jetstack.cert-manager";
      };

      src = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          Source package containing CRD YAML files.
          Use this for CRDs that come from raw YAML files (not Helm).
        '';
      };

      crds = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          List of CRD file paths within the src package.
          Only used when src is set.
        '';
        example = ["config/crd/bases/example.yaml"];
      };

      namePrefix = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional name prefix for generated CRD modules.
        '';
      };

      outputName = mkOption {
        type = types.str;
        default = "${name}-crd.nix";
        description = ''
          Output filename for the generated CRD module.
        '';
      };
    };
  });

  # Environment submodule
  envSubmodule = types.submodule ({name, ...}: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable this nixidy environment.";
      };

      module = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to the environment module that defines applications.
        '';
        example = "./_env/prod.nix";
      };

      extraModules = mkOption {
        type = types.listOf types.path;
        default = [];
        description = ''
          Additional modules to include in this environment.
        '';
      };

      branch = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Override the branch for this environment.
          If not set, uses the global nixidy.branch.
        '';
      };

      rootPath = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Override the root path for manifest output.
          Defaults to "modules/noosphere/taghmata/nixidy/manifests/<envName>".
        '';
      };
    };
  });
in {
  options.perSystem = mkPerSystemOption ({
    config,
    pkgs,
    system,
    ...
  }: {
    options.noosphere = {
      nixidy = {
      repository = mkOption {
        type = types.str;
        description = ''
          Git repository URL where rendered manifests are pushed.
        '';
        example = "https://github.com/user/repo.git";
      };

      branch = mkOption {
        type = types.str;
        default = "master";
        description = ''
          Default branch for rendered manifests.
        '';
      };

      crds = {
        enable = mkEnableOption "CRD generation" // {default = true;};

        outputPath = mkOption {
          type = types.str;
          default = "modules/noosphere/taghmata/nixidy/_generated";
          description = ''
            Output directory for generated CRD modules.
          '';
        };

        definitions = mkOption {
          type = types.attrsOf crdSubmodule;
          default = {};
          description = ''
            CRD definitions. Each entry generates:
            - A package under packages.<name>
            - An entry in the gen-crd script
            - Auto-imported into nixidy.applicationImports
          '';
          example = lib.literalExpression ''
            {
              cert-manager.chart = nixhelm.chartsDerivations.''${system}.jetstack.cert-manager;
              metallb.chart = nixhelm.chartsDerivations.''${system}.metallb.metallb;
            }
          '';
        };
      };

      extraCharts = mkOption {
        type = types.attrsOf types.path;
        default = {};
        description = ''
          Additional Helm charts beyond nixhelm.
          Keys should be "vendor/chart" format.
        '';
        example = lib.literalExpression ''
          {
            "deuxfleurs/garage" = "''${inputs.garage}/script/helm/garage";
          }
        '';
      };

      envs = mkOption {
        type = types.attrsOf envSubmodule;
        default = {};
        description = ''
          Nixidy environments to generate.
        '';
        example = lib.literalExpression ''
          {
            prod = {
              enable = true;
              module = ./nixidy/_env/prod.nix;
            };
          }
        '';
      };
      };  # close nixidy
    };  # close noosphere
  });

  config = {
    perSystem = {
      config,
      pkgs,
      system,
      ...
    }: let
      cfg = config.noosphere.nixidy;
      nixidy = self.inputs.nixidy;
      nixhelm = self.inputs.nixhelm;

      # Generate CRD package from definition
      mkCrdPackage = name: def:
        if def.chart != null
        then
          nixidy.packages.${system}.generators.fromChartCRD ({
              inherit name;
              chart = def.chart;
            }
            // lib.optionalAttrs (def.namePrefix != null) {
              namePrefix = def.namePrefix;
            })
        else if def.src != null
        then
          nixidy.packages.${system}.generators.fromCRD {
            inherit name;
            inherit (def) src crds;
          }
        else throw "CRD definition '${name}' must have either 'chart' or 'src' set";

      # Generate all CRD packages
      crdPackages = lib.mapAttrs mkCrdPackage cfg.crds.definitions;

      # Generate the gen-crd script
      genCrdScript = pkgs.writeShellScript "generate-crds" ''
        set -eo pipefail

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: def: ''
            echo "generate ${name} crds"
            cat ${crdPackages.${name}} > ${cfg.crds.outputPath}/${def.outputName}
          '')
          cfg.crds.definitions)}
      '';

      # Auto-discover CRD files from _generated directory
      autoDiscoverCrds =
        if builtins.pathExists generatedDirPath
        then let
          dirContents = builtins.readDir generatedDirPath;
          nixFiles = lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n) dirContents;
        in
          map (f: generatedDirPath + "/${f}") (builtins.attrNames nixFiles)
        else [];

      # Build enabled environments
      enabledEnvs = lib.filterAttrs (_: e: e.enable) cfg.envs;

      # Compute SSO URL if not explicitly set
      derivedSsoUrl =
        if global.sso.url != ""
        then global.sso.url
        else if global.sso.provider != "" && global.domain != ""
        then "${lib.toLower global.sso.provider}.${global.domain}"
        else "";

      # Build environment configuration for nixidy
      mkEnv = envName: envCfg: let
        effectiveBranch =
          if envCfg.branch != null
          then envCfg.branch
          else cfg.branch;

        effectiveRootPath =
          if envCfg.rootPath != null
          then envCfg.rootPath
          else "modules/noosphere/taghmata/nixidy/manifests/${envName}";

        # Combine module and extraModules
        envModules =
          lib.optional (envCfg.module != null) envCfg.module
          ++ envCfg.extraModules;
      in {
        modules =
          [
            # Noosphere options for nixidy apps
            ./_modules/noosphere-options.nix

            # Pass global values into nixidy module graph
            ({lib, ...}: {
              noosphere.domain = lib.mkDefault global.domain;
              noosphere.sso.provider = lib.mkDefault global.sso.provider;
              noosphere.sso.wellKnownUrl = lib.mkDefault global.sso.wellKnownUrl;
              noosphere.sso.url = lib.mkDefault derivedSsoUrl;
            })

            # Target configuration
            ({...}: {
              nixidy.target = {
                repository = cfg.repository;
                branch = effectiveBranch;
                rootPath = effectiveRootPath;
              };

              # Auto-import discovered CRDs
              nixidy.applicationImports = autoDiscoverCrds;
            })
          ]
          ++ envModules;
      };

      # Build charts attrset
      charts =
        nixhelm.chartsDerivations.${system}
        // lib.mapAttrs' (name: path: let
          parts = lib.splitString "/" name;
        in
          lib.nameValuePair (builtins.head parts) {${lib.last parts} = path;})
        cfg.extraCharts;
    in
      lib.mkMerge [
        # CRD packages
        (lib.mkIf cfg.crds.enable {
          packages = crdPackages;

          apps.gen-crd = {
            type = "app";
            program = genCrdScript.outPath;
          };
        })

        # Nixidy environments
        {
          legacyPackages.nixidyEnvs.${system} = nixidy.lib.mkEnvs {
            inherit pkgs;
            inherit charts;
            envs = lib.mapAttrs mkEnv enabledEnvs;
          };

          packages.nixidy = nixidy.packages.${system}.default;
        }
      ];
  };
}
