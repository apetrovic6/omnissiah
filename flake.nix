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

    woodpecker-ci = {
      url = "github:woodpecker-ci/helm";
      flake = false;
    };

    garage-operator = {
      url = "github:rajsinghtech/garage-operator";
      flake = false;
    };

    go-vikunja = {
      url = "github:go-vikunja/helm-chart";
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
      # url = "path:/home/apetrovic/clan/omnishell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    magos = {
      url = "github:apetrovic6/magos";
      # url = "path:/home/apetrovic/clan/magos";
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

    tofunix = {
      # url = "/home/apetrovic/clan/tofunix?dir=lib";
      url = "gitlab:TECHNOFAB/tofunix?dir=lib";
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

    dagger-cli = {
      url = "github:dagger/nix";
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

      noosphere = import ./modules/vars/_noosphere-values.nix;

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

        noosphere.nixidy = {
          repository = "https://github.com/apetrovic6/omnissiah.git";
          branch = "master";

          crds.definitions = {
            cert-manager.chart = nixhelm.chartsDerivations.${system}.jetstack.cert-manager;
            metallb.chart = nixhelm.chartsDerivations.${system}.metallb.metallb;
            sops-secrets-operator.chart = nixhelm.chartsDerivations.${system}.isindir.sops-secrets-operator;
            longhorn = {
              chart = nixhelm.chartsDerivations.${system}.longhorn.longhorn;
              namePrefix = "longhorn";
            };
            cloudnativepg = {
              chart = nixhelm.chartsDerivations.${system}.cloudnative-pg.cloudnative-pg;
              outputName = "cloudnativepg-crd.nix";
            };
            traefik.chart = nixhelm.chartsDerivations.${system}.traefik.traefik;
            alloy-operator.chart = nixhelm.chartsDerivations.${system}.grafana.alloy-operator;
            kube-prometheus-stack.chart = nixhelm.chartsDerivations.${system}.prometheus-community.kube-prometheus-stack;
            prometheus.chart = nixhelm.chartsDerivations.${system}.prometheus-community.prometheus;
            csi-driver-nfs.chart = nixhelm.chartsDerivations.${system}.kubernetes-csi.csi-driver-nfs;
            percona-server-mongodb-operator = {
              chart = nixhelm.chartsDerivations.${system}.percona.psmdb-operator;
              outputName = "psmdb-crd.nix";
            };

            barman-cloud.chart = nixhelm.chartsDerivations.${system}.cloudnative-pg.plugin-barman-cloud;
            garage-operator.chart = pkgs.runCommand "garage-operator-chart" {} ''
              cp -r ${self.inputs.garage-operator}/charts/garage-operator $out
            '';
          };

          # Extra charts beyond nixhelm
          extraCharts = with self.inputs; {
            "deuxfleurs/garage" = "${garage}/script/helm/garage";
            "lukasdietrich/glance-k8s" = "${glance-k8s}/charts/glance-k8s";
            "woodpecker-ci/woodpecker" = "${woodpecker-ci}/charts/woodpecker";
            "rajsinghtech/garage-operator" = "${garage-operator}/charts/garage-operator";
            "go-vikunja/vikunja" = pkgs.runCommand "vikunja-chart" {} ''
              cp -r ${go-vikunja} $out
              chmod -R u+w $out
              mkdir -p $out/charts
              tar -xzf ${pkgs.fetchurl {
                url = "https://bjw-s-labs.github.io/helm-charts/library/common-1.5.1.tgz";
                hash = "sha256-9kUXJmThPvJijV6YhhJQi2s428qkJd6WaWcstz1uNCY=";
              }} -C $out/charts
            '';
          };

          # Environments
          envs.prod = {
            enable = true;
            module = modules/noosphere/taghmata/nixidy/_env/prod.nix;
            rootPath = "modules/noosphere/taghmata/nixidy/manifests/prod";
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

        packages.tofunix = let
          tofu = inputs.tofunix.lib {inherit pkgs lib;};
        in
          tofu.mkCliAio {
            plugins = [
              (tofu.mkOpentofuProvider {
                owner = "hashicorp";
                repo = "local";
                version = "2.6.2";
                hash = "sha256-c2a7HtL1XePZs5WMLsrJ5sSdk/6VSjky37OkQpsYO8s=";
              })
              (tofu.mkOpentofuProvider {
                owner = "goharbor";
                repo = "harbor";
                version = "3.11.3";
                hash = "sha256-jBRXIBX80PdaP3urDXsBE98QkyFB14ZwUOdZ2E33pVo=";
              })

              # (tofu.mkOpentofuProvider {
              #   owner = "keycloak";
              #   repo = "keycloak";
              #   version = "5.6.0";
              #   hash = "sha256-NhXKDH82YHPHdP7pA+0VC61Sv5hCIkXjcvapqJjzhEI=";
              # })

              (tofu.mkOpentofuProvider {
                owner = "adyxax";
                repo = "forgejo";
                version = "1.5.0";
                hash = "sha256-dCK3Po8Tk+UKo2Ey4ewVdkP6l4LdCNdX8aQe+NuS824=";
              })

              # (tofu.mkOpentofuProvider {
              #   owner = "kichiyaki";
              #   repo = "woodpecker";
              #   version = "0.5.0";
              #   hash = "";
              # })

              (tofu.mkOpentofuProvider {
                owner = "carlpett";
                repo = "sops";
                version = "1.3.0";
                hash = "sha256-fs+RFt8afdzv8wyMUl+zxgGSxKOdGEerL3k3TTjio/g=";
              })
            ];
            moduleConfig = ./modules/noosphere/taghmata/_tofunix/default.nix;
          };

        # CRD packages and gen-crd app are now auto-generated by
        # modules/noosphere/taghmata/nixidy/flake-module.nix

        treefmt = {
          projectRootFile = "flake.nix";
          programs.alejandra.enable = true; # Nix formatter
          # add more: programs.prettier.enable = true; etc.
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            inputs'.clan-core.packages.clan-cli
            inputs'.nixidy.packages.default
            sops
            argocd
            nil
            nixd
            garage_2
          ];
        };
      };
    };
}
