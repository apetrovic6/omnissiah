# What the nixidy flake module (./flake-module.nix) is fed: the charts that
# CRD types are generated from, the charts that are not in nixhelm, and the
# environments.
{self, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    nixhelmCharts = self.inputs.nixhelm.chartsDerivations.${system};

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

    # nixhelm pins the ncps chart at v0.9.4, which predates the fix for
    # opaque upstream NAR URLs (kalbasit/ncps#1331, first in v0.10.0-rc10).
    # Cachix upstreams serve `nar/<uuid>.nar.zst` paths that v0.9.4 rejects
    # with HTTP 500 "invalid nar hash", which nix treats as a hard error
    # and refuses to fall through to the next substituter. Pull the fixed
    # chart directly until nixhelm catches up (or v0.10.0 goes stable).
    ncps-chart = pkgs.stdenv.mkDerivation {
      name = "helm-chart-ghcr.io-kalbasit-helm-ncps-v0.10.0-rc18";
      nativeBuildInputs = [pkgs.cacert];

      phases = ["installPhase"];
      installPhase = ''
        export HELM_CACHE_HOME="$TMP/.nix-helm-build-cache"
        out_dir="$TMP/temp-chart-output"
        mkdir -p "$out_dir"

        ${pkgs.kubernetes-helm}/bin/helm pull \
          --version v0.10.0-rc18 \
          oci://ghcr.io/kalbasit/helm/ncps \
          -d "$out_dir" \
          --untar

        mv "$out_dir/ncps" "$out"
      '';

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-UrRli9J8vorLAahyvctzxue06nHEklZYUH5p8/cqFo0=";
    };
  in {
    noosphere.nixidy = {
      repository = "https://github.com/apetrovic6/omnissiah.git";
      branch = "master";

      crds.definitions = {
        cert-manager.chart = nixhelmCharts.jetstack.cert-manager;
        metallb.chart = nixhelmCharts.metallb.metallb;
        sops-secrets-operator.chart = nixhelmCharts.isindir.sops-secrets-operator;
        longhorn = {
          chart = nixhelmCharts.longhorn.longhorn;
          namePrefix = "longhorn";
        };
        cloudnativepg = {
          chart = nixhelmCharts.cloudnative-pg.cloudnative-pg;
          outputName = "cloudnativepg-crd.nix";
        };
        traefik.chart = nixhelmCharts.traefik.traefik;
        alloy-operator.chart = nixhelmCharts.grafana.alloy-operator;
        kube-prometheus-stack.chart = nixhelmCharts.prometheus-community.kube-prometheus-stack;
        prometheus.chart = nixhelmCharts.prometheus-community.prometheus;
        csi-driver-nfs.chart = csi-driver-nfs-chart;
        ncps = {
          chart = nixhelmCharts.kalbasit.ncps;
        };

        barman-cloud.chart = nixhelmCharts.cloudnative-pg.plugin-barman-cloud;
        garage-operator.chart = pkgs.runCommand "garage-operator-chart" {} ''
          cp -r ${self.inputs.garage-operator}/charts/garage-operator $out
        '';
      };

      # Extra charts beyond nixhelm
      extraCharts = with self.inputs; {
        "kubernetes-csi/csi-driver-nfs" = csi-driver-nfs-chart;
        # Overrides the nixhelm v0.9.4 pin — see ncps-chart above.
        "kalbasit/ncps" = ncps-chart;
        # "deuxfleurs/garage" = "${garage}/script/helm/garage";
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
        module = ./_env/prod.nix;
        rootPath = "modules/noosphere/taghmata/nixidy/manifests/prod";
      };
    };
  };
}
