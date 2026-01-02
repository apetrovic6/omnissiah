{...}: {
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
        autoPrune.enable = false;
        networkSocket.listenAddress = cfgPodman.socketListenAddress;
      };

      hardware.nvidia-container-toolkit.enable = cfgPodman.enableNvidia;
    };
  };
}
