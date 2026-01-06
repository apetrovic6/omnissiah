{
  lib,
  config,
  ...
}: {
  flake.nixosModules.noosphere = {...}: let
    cfg = config.services.imperium.taghmata.rke2.registryCache;

    domain = config.noosphere.domain;

    registriesYaml = ''
      mirrors:
        "docker.io":
          endpoint:
            - "https://${cfg.harborHost}"
          rewrite:
            "^(.*)$": "${cfg.dockerProject}/$1"

        "ghcr.io":
          endpoint:
            - "https://${cfg.harborHost}"
          rewrite:
            "^(.*)$": "${cfg.ghcrProject}/$1"

      configs:
        "${cfg.harborHost}": {}
    '';
  in {
    options.services.imperium.taghmata.rke2.registryCache = {
      enable = lib.mkEnableOption "RKE2 registry mirror via Harbor proxy cache";

      harborHost = lib.mkOption {
        type = lib.types.str;
        default = "harbor.${domain}";
      };

      dockerProject = lib.mkOption {
        type = lib.types.str;
        default = "";
      };

      ghcrProject = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.etc."rancher/rke2/registries.yaml" = {
        mode = "0644";
        text = registriesYaml;
      };

      # Restart RKE2 when the registries file changes
      systemd.services = let
        regFile = config.environment.etc."rancher/rke2/registries.yaml".source;
      in
        lib.mkMerge [
          (lib.mkIf (config.systemd.services ? rke2-server) {
            rke2-server.restartTriggers = [regFile];
          })
          (lib.mkIf (config.systemd.services ? rke2-agent) {
            rke2-agent.restartTriggers = [regFile];
          })
        ];
    };
  };
}
