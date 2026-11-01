{...}: {
  flake.nixosModules.pharos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkEnableOption;

    cfg = config.services.imperium.crowdsec;
  in {
    options.services.imperium.crowdsec = {
      enable = mkEnableOption "Enable Crowdsec ";
    };

    config = mkIf cfg.enable {
      services.crowdsec = {
        enable = true;

        name = config.networking.hostName;

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

        # Upstream declares this without a default but reads it for
        # SupplementaryGroups, so it must be set.
        extraGroups = ["systemd-journal"];

        settings = {
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

          # Whitelist all Matrix API traffic — registration/auth flows generate
          # enough 401s to trigger the http-generic-401-bf ban.
          parsers.s02Enrich = [
            {
              name = "local/matrix-whitelist";
              description = "Whitelist Matrix API endpoints";
              whitelist = {
                reason = "Matrix API traffic";
                expression = [
                  "evt.Parsed.request startsWith '/_matrix/'"
                  "evt.Parsed.request startsWith '/_synapse/'"
                ];
              };
            }
          ];

          config = {
            # The rewritten module defaults data_dir to /var/lib/crowdsec/data.
            # Keep the old location so the existing DB, machine and bouncer
            # registrations survive the upgrade.
            config_paths.data_dir = "/var/lib/crowdsec/state";
            api = {
              # Enable the Local API so bouncer registration and cscli work
              server.enable = true;
              server.online_client.credentials_path = "/var/lib/crowdsec/online_api_credentials.yaml";
              # LAPI credentials for the agent to authenticate against the local API
              client.credentials_path = "/var/lib/crowdsec/state/local_api_credentials.yaml";
            };
          };

          console = {
            enrollKeyFile = config.clan.core.vars.generators.crowdsec-enroll.files."enroll-key".path;
            configuration = {
              share_manual_decisions = true;
              share_custom = true;
              share_tainted = true;
              share_context = true;
              console_management = true;
            };
          };
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

      # Ensure credential files exist (even empty) before crowdsec starts.
      # On first boot these don't exist yet, but cscli tries to open them
      # during initialization before the setup script can create them.
      systemd.tmpfiles.rules = [
        "f /var/lib/crowdsec/online_api_credentials.yaml 0640 crowdsec crowdsec -"
        # hub_dir is /var/lib/crowdsec/state/hub/ but older CrowdSec installs
        # created symlinks referencing /var/lib/crowdsec/hub/.
        # Bridge the two paths so hub item symlinks resolve correctly.
        "L+ /var/lib/crowdsec/hub - - - - /var/lib/crowdsec/state/hub"
      ];

      # CrowdSec's journalctl datasource needs journalctl in PATH.
      systemd.services.crowdsec.path = lib.mkForce [pkgs.systemd];
      # Upstream uses DynamicUser=true alongside the static crowdsec user;
      # keep the static user so state under /var/lib/crowdsec stays owned by it.
      systemd.services.crowdsec.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.crowdsec-setup.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.crowdsec-update-hub.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.crowdsec-firewall-bouncer.serviceConfig.DynamicUser = lib.mkForce false;
      # The bouncer's After= ordering and the register service's cscli config
      # lookup are now handled upstream (real /etc/crowdsec/config.yaml).

      services.crowdsec-firewall-bouncer = {
        enable = true;

        settings.mode = "iptables";
        registerBouncer = {
          enable = true;
        };
      };
    };
  };
}
