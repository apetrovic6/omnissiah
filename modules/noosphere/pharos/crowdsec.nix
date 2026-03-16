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

        localConfig.acquisitions = [
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

        settings = {
          # Enable the Local API so bouncer registration and cscli work
          general.api.server.enable = true;
          # LAPI credentials for the agent to authenticate against the local API
          lapi.credentialsFile = "/var/lib/crowdsec/state/local_api_credentials.yaml";
          console = {
            tokenFile = config.clan.core.vars.generators.crowdsec-enroll.files."enroll-key".path;
            configuration = {
              share_manual_decisions = true;
              share_custom = true;
              share_tainted = true;
              share_context = true;
              console_management = true;
            };
          };
          capi.credentialsFile = "/var/lib/crowdsec/online_api_credentials.yaml";
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

      # Upstream module uses DynamicUser=true but never sets StateDirectory,
      # so /var/lib/private/crowdsec is never created and services fail at
      # NAMESPACE setup. Disable DynamicUser since the module already creates
      # proper system users; all other sandboxing still applies.
      # Ensure credential files exist (even empty) before crowdsec starts.
      # On first boot these don't exist yet, but cscli tries to open them
      # during initialization before the setup script can create them.
      systemd.tmpfiles.rules = [
        "f /var/lib/crowdsec/online_api_credentials.yaml 0640 crowdsec crowdsec -"
        # The NixOS module sets hub_dir=/var/lib/crowdsec/state/hub/ but
        # CrowdSec creates symlinks referencing /var/lib/crowdsec/hub/.
        # Bridge the two paths so hub item symlinks resolve correctly.
        "L+ /var/lib/crowdsec/hub - - - - /var/lib/crowdsec/state/hub"
      ];

      # CrowdSec's journalctl datasource needs journalctl in PATH.
      # Upstream module sets path = mkForce [], so we must also mkForce.
      systemd.services.crowdsec.path = lib.mkForce [pkgs.systemd];
      systemd.services.crowdsec.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.crowdsec-update-hub.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.crowdsec-firewall-bouncer.serviceConfig.DynamicUser = lib.mkForce false;
      # Upstream module has Requires= but not After= for the register service,
      # so the bouncer starts before the API key file is created.
      systemd.services.crowdsec-firewall-bouncer.after = ["crowdsec-firewall-bouncer-register.service"];
      # Some nixpkgs versions use the raw cscli binary in the register service
      # instead of the NixOS wrapper, so cscli can't find /etc/crowdsec/config.yaml
      # (NixOS puts the config in the nix store). Override to use the wrapper.
      systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.ExecStart = lib.mkForce (
        pkgs.writeShellScript "crowdsec-firewall-bouncer-register-start" ''
          set -e
          cscli=/run/current-system/sw/bin/cscli
          apiKeyFile=/var/lib/crowdsec-firewall-bouncer-register/api-key.cred
          bouncerName=crowdsec-firewall-bouncer
          if $cscli bouncers list --output json | ${pkgs.jq}/bin/jq -e -- "any(.[]; .name == \"$bouncerName\")" >/dev/null; then
            if [ ! -f "$apiKeyFile" ]; then
              echo "Bouncer registered but API key is not present"
              exit 1
            fi
          else
            rm -f "$apiKeyFile"
            if ! $cscli bouncers add --output raw -- "$bouncerName" >"$apiKeyFile"; then
              rm -f "$apiKeyFile"
              exit 1
            fi
          fi
        ''
      );

      # Whitelist all Matrix API traffic — registration/auth flows generate
      # enough 401s to trigger the http-generic-401-bf ban.
      environment.etc."crowdsec/parsers/s02-enrich/matrix-whitelist.yaml".text = ''
        name: local/matrix-whitelist
        description: "Whitelist Matrix API endpoints"
        whitelist:
          reason: "Matrix API traffic"
          expression:
            - "evt.Parsed.request startsWith '/_matrix/'"
            - "evt.Parsed.request startsWith '/_synapse/'"
      '';

      users.users.crowdsec.extraGroups = ["systemd-journal"];

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
