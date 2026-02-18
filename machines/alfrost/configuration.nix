{
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
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
