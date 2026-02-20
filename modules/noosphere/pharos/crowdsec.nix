{self, ...}: {
  flake.nixosModules.pharos = {
    pkgs,
    config,
    lib,
    ...
  }: let
    inherit (lib) mkIf mkEnableOption types;

    cfg = config.services.imperium.crowdsec;
  in {
    options.services.imperium.crowdsec = {
      enable = mkEnableOption "Enable Crowdsec ";
    };

    disabledModules = [
      "services/security/crowdsec.nix"
      "services/security/crowdsec-firewall-bouncer.nix"
    ];

    imports = [
      "${self.inputs.nixpkgs-crowdsec}/nixos/modules/services/security/crowdsec.nix"
      "${self.inputs.nixpkgs-crowdsec}/nixos/modules/services/security/crowdsec-firewall-bouncer.nix"
    ];

    config = mkIf cfg.enable {
      services.crowdsec = {
        enable = true;
        package = self.inputs.nixpkgs-crowdsec.legacyPackages.${pkgs.system}.crowdsec;

        name = "alfrost";

        autoUpdateService = true;
        hub = {
          scenarios = [];
          collections = [
            "crowdsecurity/linux"
            "crowdsecurity/traefik"
            "crowdsecurity/appsec-virtual-patching"
            "crowdsecurity/appsec-generic-rules"
            "crowdsecurity/iptables"
            "crowdsecurity/sshd"
          ];

          parsers = [
            "crowdsecurity/sshd-success-logs" # Detect successful SSH logins
            "crowdsecurity/whitelists" # Prevent banning self (e.g., private IPs)
          ];
        };

        settings = {
          console.enrollKeyFile = config.clan.core.vars.generators.crowdsec-enroll.files."enroll-key".path;

          config.api.server.online_client.credentials_path = "/var/lib/crowdsec/online_api_credentials.yaml";

          acquisitions = [
            {
              journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
              labels = {type = "syslog";};
              source = "journalctl";
            }

            {
              journalctl_filter = ["_SYSTEMD_UNIT=traefik.service"];
              labels = {type = "traefik";};
              source = "journalctl";
            }
          ];
        };
      };

      clan.core.vars.generators.crowdsec-enroll = {
        files."enroll-key" = {
          secret = true;
          mode = "0400";
          owner = "crowdsec";
          group = "crowdsec";
        };

        prompts.enrollment-key = {
          description = "CrowdSec console enrollment key from app.crowdsec.net";
          type = "hidden";
          persist = true;
        };

        script = ''
          cp "$prompts/enrollment-key" "$out/enroll-key"
        '';
      };

      users.users.crowdsec.extraGroups = ["systemd-journal"];

      services.crowdsec-firewall-bouncer = {
        enable = true;
        package = self.inputs.nixpkgs-crowdsec.legacyPackages.${pkgs.system}.crowdsec-firewall-bouncer;

        settings.mode = "iptables";
        registerBouncer = {
          enable = true;
        };
      };
    };
  };
}
