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
      url = "path:/home/apetrovic/clan/nixhelm";
      # url = "github:apetrovic6/nixhelm";
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

      noosphere = {
        agePublicKey = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
        domain = "noosphere.uk";
        sso.provider = "Keycloak";
        sso.wellKnownUrl = "https://keycloak.noosphere.uk/realms/adeptus-terra/.well-known/openid-configuration";
      };

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
            barman-cloud = {
              src = pkgs.fetchFromGitHub {
                owner = "cloudnative-pg";
                repo = "plugin-barman-cloud";
                rev = "v0.10.0";
                hash = "sha256-JB0ia2qpkoJYE6GsdmQwvb6wlteCJHpIf/N16ibicgc=";
              };
              crds = ["config/crd/bases/barmancloud.cnpg.io_objectstores.yaml"];
              outputName = "barman-cloud.nix";
            };
          };

          # Extra charts beyond nixhelm
          extraCharts = {
            "deuxfleurs/garage" = "${self.inputs.garage}/script/helm/garage";
            "lukasdietrich/glance-k8s" = "${self.inputs.glance-k8s}/charts/glance-k8s";
            "woodpecker-ci/woodpecker" = "${self.inputs.woodpecker-ci}/charts/woodpecker";
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
            argocd
            nil
            nixd
            garage_2
          ];
        };
      };
    };
}
