{
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    garage = {
      url = "git+https://git.deuxfleurs.fr/Deuxfleurs/garage";
      flake = false;
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
      # url = "path:/home/apetrovic/clan/nixhelm";
      url = "github:apetrovic6/nixhelm";
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

    glance-k8s = {
      url = "github:lukasdietrich/glance-k8s";
      flake = false;
    };
  };

  outputs = inputs @ {
    self,
    flake-parts,
    import-tree,
    nixhelm,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
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

      noosphere.agePublicKey = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
      noosphere.domain = "noosphere.uk";
      noosphere.sso.provider = "Keycloak";

      # https://docs.clan.lol/guides/flake-parts
      clan = {
        imports = [./clan.nix];
      };

      perSystem = {
        pkgs,
        inputs',
        self',
        system,
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

        noosphere = {
          nixidy = {
            repository = "https://github.com/apetrovic6/omnissiah.git";
            branch = "master";
            rootPath = "modules/noosphere/taghmata/nixidy/manifests/prod";
          };

          envs.dev.enable = false;
          envs.prod = {
            enable = true;
            branch = "master";
            rootPath = "modules/noosphere/taghmata/nixidy/manifests/prod";
            extraModules = [modules/noosphere/taghmata/nixidy/_env/prod.nix];
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

        packages.alloy-operator = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "alloy-operator";
          chart = nixhelm.chartsDerivations.${system}.grafana.alloy-operator;
        };

        packages.kube-prometheus-stack = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "kube-prometheus-stack";
          chart = nixhelm.chartsDerivations.${system}.prometheus-community.kube-prometheus-stack;
        };

        packages.prometheus = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "prometheus";
          chart = nixhelm.chartsDerivations.${system}.prometheus-community.prometheus;
        };

        packages.csi-driver-nfs = inputs.nixidy.packages.${system}.generators.fromChartCRD {
          name = "csi-driver-nfs";
          chart = nixhelm.chartsDerivations.${system}.kubernetes-csi.csi-driver-nfs;
        };

        packages.barman-cloud = inputs.nixidy.packages.${system}.generators.fromCRD {
          name = "barman-cloud";
          src = pkgs.fetchFromGitHub {
            owner = "cloudnative-pg";
            repo = "plugin-barman-cloud";
            rev = "v0.10.0";
            hash = "sha256-JB0ia2qpkoJYE6GsdmQwvb6wlteCJHpIf/N16ibicgc=";
          };

          crds = [
            "config/crd/bases/barmancloud.cnpg.io_objectstores.yaml"
          ];
        };

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

                echo "generate alloy operator crds"
                cat ${self'.packages.alloy-operator} > ${path}/alloy-operator-crd.nix

                echo "generate kube prometheus stack crds"
                cat ${self'.packages.kube-prometheus-stack} > ${path}/kube-prometheus-stack-crd.nix

                echo "generate prometheus crds"
                cat ${self'.packages.prometheus} > ${path}/prometheus-crd.nix

                echo "generate csi driver nfs crds"
                cat ${self'.packages.csi-driver-nfs} > ${path}/csi-driver-nfs-crd.nix

                echo "generate barman cloud crds"
                cat ${self'.packages.barman-cloud} > ${path}/barman-cloud.nix
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
            garage_2
          ];
        };
      };
    };
}
