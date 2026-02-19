{
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  disabledModules = [
    "services/security/crowdsec.nix"
    "services/security/crowdsec-firewall-bouncer.nix"
  ];

  imports = [
    "${self.inputs.nixpkgs-crowdsec}/nixos/modules/services/security/crowdsec.nix"
    "${self.inputs.nixpkgs-crowdsec}/nixos/modules/services/security/crowdsec-firewall-bouncer.nix"
    self.inputs.omnishell.nixosModules.helix
    self.nixosModules.pharos
  ];

  disko.devices.disk.main.imageSize = "3500M"; # adjust as needed
  disko.imageBuilder.imageFormat = "qcow2"; # or "raw" (default)

  boot.growPartition = true;

  networking.nameservers = ["1.1.1.1"];

  services.pangolin = {
    enable = true;

    openFirewall = true;
    letsEncryptEmail = "cloudflare.fervor993@simplelogin.com";
    dashboardDomain = "pangolinije.ugalabugala.org";
    baseDomain = "ugalabugala.org";
    dnsProvider = "cloudflare";

    environmentFile = config.clan.core.vars.generators.pangolin.files."pangolin.env".path;

    settings = {
      flags = {
        disable_signup_without_invite = true;
        disable_user_create_org = true;
      };

      domains = {
        noosphere = {
          base_domain = "noosphere.uk";
          cert_resolver = "letsencrypt";
        };
      };
    };
  };

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
        "crowdsecurity/sshd"];

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

  # Pass Cloudflare DNS API token to Traefik for ACME DNS-01 challenge
  systemd.services.traefik.serviceConfig.EnvironmentFile = [
    config.clan.core.vars.generators.cloudflare-dns.files."cloudflare-dns.env".path
  ];

  services.dbus.enable = true;
  users.mutableUsers = false;

  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22 80 443];
    allowedUDPPorts = [22 80 21820 443];
  };

  services.openssh = {
    enable = true;
    ports = [22];
    settings = {
      PasswordAuthentication = false;
    };
  };

  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 10d";
    };
    settings = {
      trusted-users = ["apetrovic"];
      auto-optimise-store = true;
    };
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vim
    curl
    htop
  ];
}
