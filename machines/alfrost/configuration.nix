{
  self,
  config,
  pkgs,
  ...
}:
let
  pangolinOverride = pkgs.fosrl-pangolin.overrideAttrs (old: {
    version = "1.15.4";
    src = pkgs.fetchFromGitHub {
      owner = "fosrl";
      repo = "pangolin";
      rev = "1.15.4";
      hash = "sha256-HayJqkLp2/+V+TufsINK4uVeQ2vAdvQnvT7Fz57gAyU=";
    };

    preBuild = ''
      npm run set:oss
      npm run set:sqlite
      npm run db:generate
    '';

    buildPhase = ''
      runHook preBuild
      npm run build
      npm run build:cli
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/{bin,share/pangolin}

      cp -r node_modules $out/share/pangolin

      cp -r .next/standalone/.next $out/share/pangolin
      cp .next/standalone/package.json $out/share/pangolin

      cp -r .next/static $out/share/pangolin/.next/static
      cp -r public $out/share/pangolin/public

      cp -r dist $out/share/pangolin/dist

      cp server/db/names.json $out/share/pangolin/dist/names.json
      cp server/db/ios_models.json $out/share/pangolin/dist/ios_models.json
      cp server/db/mac_models.json $out/share/pangolin/dist/mac_models.json

      runHook postInstall
    '';
  });

in
 {

  imports = [
    self.inputs.omnishell.nixosModules.helix
    self.nixosModules.pharos
  ];

  disko.devices.disk.main.imageSize = "3500M"; # adjust as needed
  disko.imageBuilder.imageFormat = "qcow2"; # or "raw" (default)

  boot.growPartition = true;

  networking.nameservers = ["1.1.1.1"];

  services.traefik.staticConfigOptions.accesslog.filepath = {};

  services.pangolin = {
    enable = true;

    package = pangolinOverride;
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

  services.imperium.crowdsec.enable = true;


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
