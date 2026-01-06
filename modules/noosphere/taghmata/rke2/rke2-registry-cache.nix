{...}: {
  flake.nixosModules.noosphere = {
    lib,
    pkgs,
    config,
    ...
  }: let
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
      # Restart RKE2 when registries.yaml changes (without referencing config.systemd.services)
      systemd.services.rke2-restart-on-registries-change = {
        description = "Restart rke2 when /etc/rancher/rke2/registries.yaml changes";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.bash}/bin/bash -lc ''
          ${pkgs.systemd}/bin/systemctl try-restart rke2-server.service || true
          ${pkgs.systemd}/bin/systemctl try-restart rke2-agent.service || true
        ''";
        };
      };

      systemd.paths.rke2-registries = {
        description = "Watch rke2 registries.yaml";
        wantedBy = ["multi-user.target"];
        pathConfig = {
          PathChanged = "/etc/rancher/rke2/registries.yaml";
          Unit = "rke2-restart-on-registries-change.service";
        };
      };
    };
  };
}
