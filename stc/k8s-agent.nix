{...}: {
  _class = "clan.service";
  manifest.name = "k8s-agent";
  manifest.readme = "";

  roles.default.description = "Rke2 agent (worker) node config";

  roles.default.perInstance.nixosModule = {
    config,
    lib,
    pkgs,
    self,
    ...
  }: {
    imports = [
      self.nixosModules.noosphere
    ];

    nixpkgs.overlays = [
      self.overlays.rke2
    ];

    services.imperium.taghmata.rke2.registryCache = {
      enable = true;
      dockerProject = "docker_cache";

      # ghcr.io is deliberately NOT mirrored, to keep CNPG off Harbor.
      #
      # Harbor's own database is a CNPG cluster, so routing
      # ghcr.io/cloudnative-pg/* through Harbor makes Harbor a prerequisite for
      # starting the thing Harbor depends on. On 2026-10-02 that closed into a
      # deadlock: a node lost the Longhorn CSI driver, the Harbor DB primary
      # living on it could not restart, Harbor served nothing, and the node had
      # no working mirror to pull its way out. It took ~17 minutes to break out
      # on its own, via containerd's last-resort fallback to the upstream.
      #
      # This cannot be expressed as an exclusion: RKE2 mirror keys are
      # hostnames only, so the choice is per registry, not per repository.
      # ghcr.io costs little to give up -- 12 distinct images cluster-wide
      # against 63 on docker.io -- and four of those twelve are the CNPG ones
      # this is about.
      #
      # Still unbroken, and not fixable the same way: docker.io/goharbor/* and
      # docker.io/longhornio/* are the other two links, and dropping the
      # docker.io mirror wholesale is too high a price. Those need the images
      # preloaded on every node instead.
      ghcrProject = null;
    };

    # Calico's VXLAN traffic arrives on an interface other than the one the
    # route table would pick for the source address, so strict reverse-path
    # filtering drops it.
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
    };

    services.rke2.package = pkgs.rke2_1_35;

    # No autoDeployCharts / manifests block here, unlike the server roles:
    # charts and manifests are applied by server nodes only. An agent that
    # declared them would just be carrying dead config.
    services.imperium.taghmata.rke2.agent = rec {
      enable = true;
      clusterName = "taghmata-omnissiah";

      serverAddr = "https://192.168.1.138:9345";

      tokenFile = config.clan.core.vars.generators.taghmata-node-token.files.node-token.path;

      nodeLabels = [
        "role=worker"
        "cluster=${clusterName}"
      ];

      # This is the only non-amd64 node in the cluster, and the scheduler does
      # not know anything about image architecture -- it places the pod, then
      # the kubelet pulls, and an image with no arm64 manifest dies with
      # `exec format error`. Without this taint every existing x86-only
      # Deployment becomes a coin flip on each reschedule.
      #
      # Workloads opt in explicitly instead, with a matching toleration (and a
      # nodeSelector of kubernetes.io/arch=arm64 if they must land here rather
      # than merely being allowed to). DaemonSets with blanket tolerations --
      # Longhorn's manager above all -- still need excluding by nodeSelector.
      nodeTaints = ["arch=arm64:NoSchedule"];

      openFirewall = true;
    };
  };
}
