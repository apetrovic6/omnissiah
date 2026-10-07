{...}: {
  flake.nixosModules.noosphere = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.services.imperium.taghmata.rke2.registryCache;

    domain = config.noosphere.domain;

    # One mirror block per upstream registry proxied through Harbor.
    #
    # A registry whose project is null is left out of the file entirely, which
    # is the only way to keep a given image off Harbor: RKE2 mirror keys are
    # registry hostnames, with no repository-path scoping, and the `rewrite`
    # regexes are Go RE2 -- no negative lookahead -- so a mirror cannot be made
    # to carve out one repository under a host it otherwise proxies.
    mirrorLines = registry: project: [
      "  \"${registry}\":"
      "    endpoint:"
      "      - \"https://${cfg.harborHost}\""
      "    rewrite:"
      "      \"^(.*)$\": \"${project}/$1\""
    ];

    registriesYaml = lib.concatStringsSep "\n" (
      ["mirrors:"]
      ++ lib.optionals (cfg.dockerProject != null) (mirrorLines "docker.io" cfg.dockerProject)
      ++ lib.optionals (cfg.ghcrProject != null) (mirrorLines "ghcr.io" cfg.ghcrProject)
      ++ [
        ""
        "configs:"
        "  \"${cfg.harborHost}\": {}"
        ""
      ]
    );
  in {
    options.services.imperium.taghmata.rke2.registryCache = {
      enable = lib.mkEnableOption "RKE2 registry mirror via Harbor proxy cache";

      harborHost = lib.mkOption {
        type = lib.types.str;
        default = "harbor.${domain}";
      };

      dockerProject = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Harbor proxy-cache project backing docker.io, or null to leave
          docker.io unmirrored so containerd pulls it directly.
        '';
      };

      ghcrProject = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Harbor proxy-cache project backing ghcr.io, or null to leave ghcr.io
          unmirrored so containerd pulls it directly.
        '';
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
