{config, ...}: let
  globalCfg = config;
in {
  flake.nixosModules.virtualisation = {
    config,
    lib,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.virtualisation;
    cfgPodman = cfg.podman;
  in {
    options.services.imperium.virtualisation.podman = {
      enable = mkEnableOption "Enable Podman";

      enableDockerSocket = mkOption {
        type = types.bool;
        description = "Make the Podman socket available in place of the Docker socket, so Docker tools can find the Podman socket.";
        default = false;
      };


      enableDockerCompat = mkOption {
        type = types.bool;
        description = "Create an alias mapping docker to podman.";
        default = false;
      };

      enableNvidia = mkOption {
        type = types.bool;
        description = "Enable use of Nvidia GPUs within podman containers. (Uses hardware.nvidia-container-toolkit.enable)";
        default = false;
      };

      socketListenAddress = mkOption {
        type = types.str;
        description = "Interface for receiving TLS connections";
        default = "0.0.0.0";
      };
    };

    config = mkIf cfgPodman.enable {
      virtualisation.podman = {
        enable = true;
        dockerSocket.enable = cfgPodman.enableDockerSocket;
        dockerCompat = cfgPodman.enableDockerCompat;
        autoPrune.enable = false;
        networkSocket.listenAddress = cfgPodman.socketListenAddress;
      };

      hardware.nvidia-container-toolkit.enable = cfgPodman.enableNvidia;
      virtualisation.containers = let
        domain = globalCfg.noosphere.domain;
      in {
        enable = true;
        # v2 registries.conf: the deprecated `registries.search` renders a v1
        # file, which newer skopeo/podman reject ("must be in v2 format").
        registries.settings = {
          unqualified-search-registries = [
            "docker.io"
            "ghcr.io"
            "quay.io"
          ];
        };
      };

      # Manual registries.conf for pull-through cache support
      # This configures Harbor proxy cache projects as mirrors with path rewriting
      environment.etc."containers/registries.conf.d/harbor-mirrors.conf".text = let
        domain = globalCfg.noosphere.domain;
      in ''
        # Harbor pull-through cache configuration
        # Images will be automatically cached in Harbor when pulled
        # The location includes the project path, effectively rewriting:
        #   podman pull nginx -> harbor.${domain}/docker_cache/library/nginx
        #   podman pull ghcr.io/foo/bar -> harbor.${domain}/github_cache/foo/bar

        [[registry]]
        prefix = "docker.io"
        location = "docker.io"

        [[registry.mirror]]
        location = "harbor.${domain}/docker_cache"
        insecure = false

        [[registry]]
        prefix = "ghcr.io"
        location = "ghcr.io"

        [[registry.mirror]]
        location = "harbor.${domain}/github_cache"
        insecure = false
      '';
    };
  };
}
