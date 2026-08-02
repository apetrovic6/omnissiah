{
  self,
  config,
  pkgs,
  ...
}: let
  domain = "ugalabugala.org";
in {
  imports = [
    self.nixosModules.pharos
  ];

  nixpkgs.overlays = [
    self.overlays.helix
  ];

  disko.devices.disk.main.imageSize = "3500M"; # adjust as needed
  disko.imageBuilder.imageFormat = "qcow2"; # or "raw" (default)

  boot.growPartition = true;

  networking.nameservers = ["1.1.1.1"];

  services.traefik.staticConfigOptions.accesslog.filepath = {};

  services.imperium.crowdsec.enable = true;

  # systemd.services.traefik.serviceConfig.EnvironmentFile = [
  #   config.clan.core.vars.generators.cloudflare-dns.files."cloudflare-dns.env".path
  # ];

  services.dbus.enable = true;
  users.mutableUsers = false;

  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22 80 443];
    allowedUDPPorts = [22 80 443 21820];
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

  environment.systemPackages = with pkgs; [
    helix
    vim
    curl
    htop
  ];
}
