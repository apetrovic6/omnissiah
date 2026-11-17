# nixidy for flake-parts.
#
# nixidy renders Kubernetes manifests from Nix modules and ships no flake-parts
# support of its own. This module provides it, and knows nothing about this
# repository: what is specific to the taghmata cluster is in ./taghmata.nix.
#
# Any flake-parts module can contribute to an environment:
#
#   {
#     # An application: a nixidy module, evaluated when the environment is built.
#     nixidy.envs.prod.apps.ncps = {charts, ...}: {
#       applications.ncps = { ... };
#     };
#
#     perSystem = {pkgs, ...}: {
#       # A chart nixhelm does not have, as `charts.<vendor>.<chart>`.
#       nixidy.charts."kalbasit/ncps" = ./chart;
#       # Typed options for a chart's custom resources.
#       nixidy.crds.definitions.ncps.chart = ./chart;
#     };
#   }
#
# Outputs:
#   nixidyEnvs.<system>.<env>    the environments, where the nixidy CLI looks
#                                (`nixidy switch .#prod`)
#   nixidyCrds.<system>.<name>   the generated option modules for CRDs
#   nixidyChecks.<system>.<env>  fails when the committed manifests are not what
#                                the environment renders. Not in `checks`: it goes
#                                red on every chart bump until someone renders.
#   apps.<system>.render-<env>   `nixidy switch` for the environment, from the
#                                repository root
#   apps.<system>.gen-crd        writes those into crds.outputPath
#   packages.<system>.nixidy     the nixidy CLI
{
  self,
  lib,
  flake-parts-lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkEnableOption types;
  inherit (flake-parts-lib) mkPerSystemOption;

  top = config.nixidy;

  crdSubmodule = types.submodule ({name, ...}: {
    options = {
      chart = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "Helm chart to generate the CRD options from.";
        example = "nixhelm.chartsDerivations.\${system}.jetstack.cert-manager";
      };

      src = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "Source containing CRD YAML files, for CRDs that do not come from a chart.";
      };

      crds = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Paths of the CRD files within `src`.";
        example = ["config/crd/bases/example.yaml"];
      };

      namePrefix = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Name prefix for the generated options.";
      };

      outputName = mkOption {
        type = types.str;
        default = "${name}-crd.nix";
        description = "File name of the generated module in `crds.outputPath`.";
      };
    };
  });

  envSubmodule = types.submodule ({name, ...}: {
    options = {
      enable = mkEnableOption "this environment" // {default = true;};

      branch = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Branch the rendered manifests are read from. Default: `nixidy.branch`.";
      };

      rootPath = mkOption {
        type = types.str;
        default = "./manifests/${name}";
        description = "Directory in the repository the manifests are rendered to.";
      };

      modules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = "nixidy modules of this environment that are not a single application.";
      };

      apps = mkOption {
        type = types.attrsOf types.deferredModule;
        default = {};
        description = ''
          The applications of this environment, each a nixidy module. The name
          is only a handle for `disabledApps`; a module may define several
          `applications`.
        '';
      };

      disabledApps = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Names from `apps` to leave out of this environment.";
      };
    };
  });
in {
  options.nixidy = {
    repository = mkOption {
      type = types.str;
      description = "Git repository ArgoCD reads the rendered manifests from.";
      example = "https://github.com/user/repo.git";
    };

    branch = mkOption {
      type = types.str;
      default = "master";
      description = "Branch the rendered manifests are read from.";
    };

    modules = mkOption {
      type = types.listOf types.deferredModule;
      default = [];
      description = "nixidy modules included in every environment.";
    };

    applicationImports = mkOption {
      # Not deferredModule: nixidy takes these as paths or functions, and a
      # deferred module is an attribute set.
      type = types.listOf types.raw;
      default = [];
      description = "Modules (paths or functions) imported into every application, for options of your own.";
    };

    extraSpecialArgs = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = {};
      description = "Arguments passed to every nixidy module.";
    };

    envs = mkOption {
      type = types.attrsOf envSubmodule;
      default = {};
      description = "The environments to render.";
    };
  };

  options.perSystem = mkPerSystemOption ({...}: {
    options.nixidy = {
      charts = mkOption {
        type = types.attrsOf types.path;
        default = {};
        description = ''
          Helm charts beyond nixhelm's, keyed "vendor/chart" and available to
          modules as `charts.<vendor>.<chart>`. A vendor given here replaces
          nixhelm's entry for that vendor.
        '';
        example = lib.literalExpression ''
          { "deuxfleurs/garage" = "''${inputs.garage}/script/helm/garage"; }
        '';
      };

      crds = {
        enable = mkEnableOption "CRD option generation" // {default = true;};

        outputPath = mkOption {
          type = types.str;
          description = "Directory in the repository `gen-crd` writes the generated modules to.";
        };

        generatedDir = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            The same directory as a path. Every .nix file in it is imported
            into every application.
          '';
        };

        definitions = mkOption {
          type = types.attrsOf crdSubmodule;
          default = {};
          description = "CRDs to generate options for.";
        };
      };
    };
  });

  config = {
    # perSystem.nixidyEnvs, .nixidyCrds and .nixidyChecks become
    # nixidyEnvs.<system>, nixidyCrds.<system> and nixidyChecks.<system> on the
    # flake.
    transposition.nixidyEnvs.adHoc = true;
    transposition.nixidyCrds.adHoc = true;
    transposition.nixidyChecks.adHoc = true;

    perSystem = {
      config,
      pkgs,
      system,
      ...
    }: let
      cfg = config.nixidy;
      nixidy = self.inputs.nixidy;
      nixhelm = self.inputs.nixhelm;

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
        else throw "nixidy.crds.definitions.${name} must set `chart` or `src`";

      crdPackages = lib.mapAttrs mkCrdPackage cfg.crds.definitions;

      genCrdScript = pkgs.writeShellScript "generate-crds" ''
        set -eo pipefail

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: def: ''
            echo "generate ${name} crds"
            cat ${crdPackages.${name}} > ${cfg.crds.outputPath}/${def.outputName}
          '')
          cfg.crds.definitions)}
      '';

      generatedCrds =
        if cfg.crds.generatedDir != null && builtins.pathExists cfg.crds.generatedDir
        then
          map (file: cfg.crds.generatedDir + "/${file}") (builtins.attrNames (
            lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name)
            (builtins.readDir cfg.crds.generatedDir)
          ))
        else [];

      mkEnv = envName: env: {
        modules =
          top.modules
          ++ [
            {
              nixidy.target = {
                inherit (top) repository;
                branch =
                  if env.branch != null
                  then env.branch
                  else top.branch;
                inherit (env) rootPath;
              };

              nixidy.applicationImports = generatedCrds ++ top.applicationImports;
            }
          ]
          ++ env.modules
          ++ lib.attrValues (removeAttrs env.apps env.disabledApps);
      };

      enabledEnvs = lib.filterAttrs (_: env: env.enable) top.envs;

      # Fails when the manifests committed in the repository are not what the
      # environment renders: after an input update that moved a chart, or a
      # source change nobody rendered.
      mkDriftCheck = envName: env:
        pkgs.runCommand "nixidy-manifests-${envName}" {
          rendered = config.nixidyEnvs.${envName}.environmentPackage;
          committed = "${self}/${env.rootPath}";
        } ''
          if diff -r "$rendered" "$committed" > diff.txt; then
            touch "$out"
            exit 0
          fi

          # nix shows the end of a failed build's log, so the summary goes last.
          strip() { sed -e "s#$rendered/##g" -e "s#$committed/##g" -e "s#$rendered#(rendered)#g" -e "s#$committed#(committed)#g"; }
          diff -rq "$rendered" "$committed" | strip > files.txt || true

          echo "Files that differ:"
          head -60 files.txt
          echo
          echo "By application:"
          awk '
            $1 == "Files" { split($2, p, "/"); print p[1] }
            $1 == "Only"  { d = $3; sub(/:$/, "", d); split(d, p, "/"); print (p[1] ~ /^\(/ ? $4 : p[1]) }
          ' files.txt | sort | uniq -c
          echo
          echo "$(wc -l < files.txt) file(s) in ${env.rootPath} are not what ${envName} renders."
          echo "Render them with: nix run .#render-${envName}"
          exit 1
        '';

      # Renders an environment into the repository, from anywhere inside it.
      mkRenderApp = envName: _: {
        type = "app";
        program =
          (pkgs.writeShellScript "render-${envName}" ''
            set -euo pipefail
            cd "$(${lib.getExe pkgs.git} rev-parse --show-toplevel)"
            exec ${lib.getExe' nixidy.packages.${system}.default "nixidy"} switch ".#${envName}" "$@"
          '').outPath;
      };

      charts =
        nixhelm.chartsDerivations.${system}
        // lib.mapAttrs' (name: path: let
          parts = lib.splitString "/" name;
        in
          lib.nameValuePair (builtins.head parts) {${lib.last parts} = path;})
        cfg.charts;
    in
      lib.mkMerge [
        (lib.mkIf cfg.crds.enable {
          nixidyCrds = crdPackages;

          apps.gen-crd = {
            type = "app";
            program = genCrdScript.outPath;
          };
        })

        {
          nixidyEnvs = nixidy.lib.mkEnvs {
            inherit pkgs charts;
            inherit (top) extraSpecialArgs;
            envs = lib.mapAttrs mkEnv enabledEnvs;
          };

          nixidyChecks = lib.mapAttrs mkDriftCheck enabledEnvs;

          apps = lib.mapAttrs' (envName: env: lib.nameValuePair "render-${envName}" (mkRenderApp envName env)) enabledEnvs;

          packages.nixidy = nixidy.packages.${system}.default;
        }
      ];
  };
}
