{
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";

    nixpkgs.follows = "nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "clan-core/nixpkgs";

    nix-flatpak.url = "github:gmodena/nix-flatpak?ref=latest";

    impermanence.url = "github:nix-community/impermanence";

    import-tree.url = "github:vic/import-tree";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    omnishell = {
      url = "github:apetrovic6/omnishell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    magos = {
      url = "github:apetrovic6/magos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvirt = {
      url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixhelm = {
      url = "github:nix-community/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nvf = {
      url = "github:apetrovic6/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = inputs @ {
    self,
    flake-parts,
    import-tree,
    nixidy,
    nixhelm,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} rec {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        inputs.clan-core.flakeModules.default
        inputs.treefmt-nix.flakeModule
        (import-tree ./modules)
      ];

      flake.nixidyEnvs = inputs.nixpkgs.lib.genAttrs systems (system: let
        pkgsForSystem = import inputs.nixpkgs {inherit system;};
      in
        inputs.nixidy.lib.mkEnvs {
          pkgs = pkgsForSystem;
          charts = nixhelm.chartsDerivations.${system};
          envs = {
            # dev.modules = [./taghmata/env/dev.nix];
            prod.modules = [./modules/noosphere/taghmata/nixidy/_env/prod.nix];
          };
        });

      # https://docs.clan.lol/guides/flake-parts
      clan = {
        imports = [./clan.nix];
      };

      perSystem = {
        pkgs,
        inputs',
        self',
        system,
        lib,
        ...
      }: {
        checks = {
          enginseer =
            self.nixosConfigurations.enginseer.config.system.build.toplevel;
          sol = self.nixosConfigurations.sol.config.system.build.toplevel;
          terra = self.nixosConfigurations.terra.config.system.build.toplevel;
          luna = self.nixosConfigurations.luna.config.system.build.toplevel;
          phalanx = self.nixosConfigurations.phalanx.config.system.build.toplevel;
        };

        legacyPackages = {
          nixidyEnvs.${system} = inputs.nixidy.lib.mkEnvs {
            inherit pkgs;

            charts = inputs.nixhelm.chartsDerivations.${system};

            envs = {
              prod.modules = [modules/noosphere/taghmata/nixidy/_env/prod.nix];
            };
          };
        };

        packages.ci =
          pkgs.runCommand "ci-build" {
            # All check paths as a space-separated env var
            checkPaths = builtins.attrValues self'.checks;
          } ''
            mkdir -p "$out"
            # Just symlink everything into $out; works for files AND dirs
            for p in $checkPaths; do
              ln -s "$p" "$out"/
            done
          '';

        packages.nixidy = inputs'.nixidy.packages.default;

        packages.certManager = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "cert-manager";

          chart = nixhelm.chartsDerivations.${system}.jetstack.cert-manager;
        };

        packages.metallb = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "metallb";
          chart = nixhelm.chartsDerivations.${system}.metallb.metallb;
        };

        packages.sops-secrets-operator = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "sops-secrets-operator";
          chart = nixhelm.chartsDerivations.${system}.isindir.sops-secrets-operator;
        };

        packages.longhorn = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "longhorn";
          namePrefix = "longhorn";
          chart = nixhelm.chartsDerivations.${system}.longhorn.longhorn;
        };

        packages.cloudnativepg = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "cloudnative-pg";
          chart = nixhelm.chartsDerivations.${system}.cloudnative-pg.cloudnative-pg;
        };

        packages.traefik = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "traefik";
          chart = nixhelm.chartsDerivations.${system}.traefik.traefik;
        };

        # packages.zitadel= inputs.nixidy.packages.${system}.generators.fromChartCRD {
        #   name = "zitadel";
        #   chart = nixhelm.chartsDerivations.${system}.zitadel.zitadel;
        # };

        # packages.seerr = inputs.nixidy.packages.${system}.generators.fromChartCRD {
        #   name = "seerr";
        #   chartAttrs = {
        #     repo = "oci://ghcr.io/fallenbagel/jellyseerr/jellyseerr-chart";
        #     chart = "seerr-chart";
        #     version = "3.0.0";
        #     chartHash = lib.fakeHash;
        #   };
        # };

        apps = {
          gen-crd = let
            path = "modules/noosphere/taghmata/nixidy/_generated";
          in {
            type = "app";
            program =
              (pkgs.writeShellScript "generate-modules" ''
                set -eo pipefail

                echo "generate cert manager crds"
                cat ${self'.packages.certManager} > ${path}/cert-manager-crd.nix

                echo "generate longhorn crds"
                cat ${self'.packages.longhorn} > ${path}/longhorn-crd.nix

                echo "generate metallb crds"
                cat ${self'.packages.metallb} > ${path}/metallb-crd.nix

                echo "generate cloudnative pg crds"
                cat ${self'.packages.cloudnativepg} > ${path}/cloudnativepg-crd.nix

                echo "generate sops-secrets-operator crds"
                cat ${self'.packages.sops-secrets-operator} > ${path}/sops-secrets-operator-crd.nix

                echo "generate traefik crds"
                cat ${self'.packages.traefik} > ${path}/traefik-crd.nix

              '').outPath;
          };
        };

        treefmt = {
          projectRootFile = "flake.nix";
          programs.alejandra.enable = true; # Nix formatter
          # add more: programs.prettier.enable = true; etc.
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            inputs'.clan-core.packages.clan-cli
            inputs'.nixidy.packages.default
            argocd
            nil
            nixd
          ];
        };
      };
    };
}
