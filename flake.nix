{
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-26.05";

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
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

    nix-jetbrains-plugins.url = "github:nix-community/nix-jetbrains-plugins";

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
      url = "github:nix-community/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tofunix = {
      # url = "/home/apetrovic/clan/tofunix?dir=lib";
      url = "gitlab:TECHNOFAB/tofunix?dir=lib";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

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

    homebrew-quickemu = {
      url = "github:quickemu-project/homebrew-quickemu";
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
    # nixpkgs,
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
        (import-tree ./overlays)
      ];

      noosphere = import ./modules/vars/_noosphere-values.nix;

      # https://docs.clan.lol/guides/flake-parts
      clan = {
        imports = [./clan.nix];
        pkgsForSystem = system:
          import inputs.nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              allowInsecurePredicate = pkg: inputs.nixpkgs.lib.getName pkg == "librewolf";
              permittedInsecurePackages = ["librewolf-151.0.2-1"];
            };
            nix.settings.extra-experimental-features = ["pipe-operators"];
          };
      };

      perSystem = {
        pkgs,
        inputs',
        self',
        system,
        lib,
        ...
      }: let
        # nixhelm's kubernetes-csi/csi-driver-nfs pin is unusable:
        #   - its default (version 0.0.0) is the master *dev* chart, which
        #     defaults to gcr.io/k8s-staging-sig-storage/nfsplugin:canary and
        #     passes --max-snapshot-* flags the cached canary binary rejects,
        #     crashlooping csi-nfs-controller;
        #   - its 4.13.4 pin records a chartHash that doesn't match the
        #     published tarball.
        # Fetch the released chart directly instead.
        csi-driver-nfs-chart = pkgs.fetchzip {
          url = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts/v4.13.4/csi-driver-nfs-4.13.4.tgz";
          hash = "sha256-4WszOpzLQ5tMIWgLQRLfBQVgf3hBOxYqsEpDyy3/lE4=";
        };

        # nixhelm pins dagger-helm to the vanity host oci://registry.dagger.io,
        # which is a proxy in front of ghcr.io. Its 401 challenge advertises
        #   scope="repository:dagger-helm:pull"
        # with no owner segment, so ghcr.io's token endpoint rejects it:
        #   GET https://ghcr.io/token?scope=repository%3Adagger-helm%3Apull
        #   -> 400 name invalid: invalid repository name
        # That makes charts.dagger-helm.dagger-helm unfetchable and fails the
        # whole prod env. The identical artifact is served from the real
        # repository, so pull it from there. Same body as nix-kube-generators'
        # downloadHelmChart; inlined to avoid taking on another flake input.
        dagger-helm-chart = pkgs.stdenv.mkDerivation {
          name = "helm-chart-ghcr.io-dagger-dagger-helm-0.21.9";
          nativeBuildInputs = [pkgs.cacert];

          phases = ["installPhase"];
          installPhase = ''
            export HELM_CACHE_HOME="$TMP/.nix-helm-build-cache"
            out_dir="$TMP/temp-chart-output"
            mkdir -p "$out_dir"

            ${pkgs.kubernetes-helm}/bin/helm pull \
              --version 0.21.9 \
              oci://ghcr.io/dagger/dagger-helm \
              -d "$out_dir" \
              --untar

            mv "$out_dir/dagger-helm" "$out"
          '';

          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-TubGkb8PB79zLFfcEuqm4AFzxW0SmMZumubTlCS7GWY=";
        };
      in {
        checks = {
          enginseer =
            self.nixosConfigurations.enginseer.config.system.build.toplevel;
          sol = self.nixosConfigurations.sol.config.system.build.toplevel;
          terra = self.nixosConfigurations.terra.config.system.build.toplevel;
          luna = self.nixosConfigurations.luna.config.system.build.toplevel;
          phalanx = self.nixosConfigurations.phalanx.config.system.build.toplevel;
          cerberus = self.nixosConfigurations.cerberus.config.system.build.toplevel;
          alfrost = self.nixosConfigurations.alfrost.config.system.build.toplevel;
          cypramundi = self.nixosConfigurations.cypramundi.config.system.build.toplevel;
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
            csi-driver-nfs.chart = csi-driver-nfs-chart;
            ncps = {
              chart = nixhelm.chartsDerivations.${system}.kalbasit.ncps;
            };

            barman-cloud.chart = nixhelm.chartsDerivations.${system}.cloudnative-pg.plugin-barman-cloud;
            garage-operator.chart = pkgs.runCommand "garage-operator-chart" {} ''
              cp -r ${self.inputs.garage-operator}/charts/garage-operator $out
            '';
          };

          # Extra charts beyond nixhelm
          extraCharts = with self.inputs; {
            "kubernetes-csi/csi-driver-nfs" = csi-driver-nfs-chart;
            "dagger-helm/dagger-helm" = dagger-helm-chart;
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
                version = "2.9.1";
                hash = "sha256-awO5iaFNVaN3CYjS0ZauX+E7uuQ19tgZPPSSVTuOjq0=";
              })
              (tofu.mkOpentofuProvider {
                owner = "goharbor";
                repo = "harbor";
                version = "3.12.5";
                hash = "sha256-DuGy/HBCVR4HKn9dwHzLeQbIakAOYndGvogX6RILmyc=";
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
                version = "1.5.8";
                hash = "sha256-SCw6/yyBlwRNPA3J2gcb/0WIQMxgtFSLnMvDs9besLE=";
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
                version = "1.4.1";
                hash = "sha256-56pJdj4qrcCpZ3BoB5Uw5NEZ1x6fH+uIV39UOkPKpg4=";
              })

              (tofu.mkOpentofuProvider {
                owner = "trozz";
                repo = "pocketid";
                version = "2.3.0";
                hash = "sha256-splZqWbXZHqXBTz0eNiKYE7QlCPPOlyMt40+5mFlF88=";
              })

              (tofu.mkOpentofuProvider {
                owner = "hashicorp";
                repo = "kubernetes";
                version = "3.2.1";
                hash = "sha256-Sh2s1fyGrtSQG/V2yT1wQxT32j+vlYVpTFeJmFcxMzo=";
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
