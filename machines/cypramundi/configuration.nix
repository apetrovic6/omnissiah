{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  pangolinOverride = pkgs.fosrl-pangolin.overrideAttrs (old: {
    version = "1.16.2";
    src = pkgs.fetchFromGitHub {
      owner = "fosrl";
      repo = "pangolin";
      rev = "1.16.2";
      hash = "sha256-pWD2VinfkCiSSP6/einXgduKQ8lzWdHlrj2eqUU/x6Y=";
    };

    npmDeps = pkgs.fetchNpmDeps {
      name = "pangolin-1.16.2-npm-deps";
      src = pkgs.fetchFromGitHub {
        owner = "fosrl";
        repo = "pangolin";
        rev = "1.16.2";
        hash = "sha256-pWD2VinfkCiSSP6/einXgduKQ8lzWdHlrj2eqUU/x6Y=";
      };
      hash = "sha256-CwS26eRAIuxJ2fekRRapDWYAOHXPV0mIX/by4uW2ZOM=";
    };

    postPatch = ''
      substituteInPlace src/app/layout.tsx --replace-fail \
        '{ Inter } from "next/font/google"' \
        'localFont from "next/font/local"'

      substituteInPlace src/app/layout.tsx --replace-fail \
        'Inter({' \
        'localFont({'

      substituteInPlace src/app/layout.tsx --replace-fail \
        'subsets: ["latin"]' \
        "src: './Inter.ttf'"

      cp "${pkgs.inter}/share/fonts/truetype/InterVariable.ttf" src/app/Inter.ttf
    '';

    preBuild = ''
      npm run set:oss
      npm run set:pg
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
      cp -r server/migrations $out/share/pangolin/dist/init

      cp server/db/names.json $out/share/pangolin/dist/names.json
      cp server/db/ios_models.json $out/share/pangolin/dist/ios_models.json
      cp server/db/mac_models.json $out/share/pangolin/dist/mac_models.json

      runHook postInstall
    '';
  });

  domain = "ugalabugala.org";
in {
  imports = [
    # self.inputs.omnishell.nixosModules.helix
    self.nixosModules.postgresql
    self.nixosModules.pharos
  ];

  disko.devices.disk.main.imageSize = "3500M"; # adjust as needed
  disko.imageBuilder.imageFormat = "qcow2"; # or "raw" (default)

  boot.growPartition = true;

  networking.nameservers = ["1.1.1.1"];

  services.traefik.staticConfigOptions.accesslog.filepath = {};

  services.imperium.postgresql = {
    enable = true;

    authentication = ''
      # TYPE  DATABASE  USER      ADDRESS         METHOD
      local   all       all                       peer
      host    pangolin  pangolin  127.0.0.1/32    scram-sha-256
    '';

    listenAddresses = "127.0.0.1";
    backup = {
      enable = true;
      location = "/var/pg_backup/";
      startAt = "*-*-* 01:15:00";
    };

    users.pangolin = {
      databases = ["pangolin"];
      ensureDBOwnership = true;
      passwordDependency = "pangolin";
    };
  };

  services.pangolin = {
    enable = true;

    package = pangolinOverride;
    openFirewall = true;
    letsEncryptEmail = "cloudflare.fervor993@simplelogin.com";
    dashboardDomain = domain;
    baseDomain = domain;
    dnsProvider = "cloudflare";

    environmentFile = config.clan.core.vars.generators.pangolin.files."pangolin.env".path;

    settings = {
      flags = {
        disable_signup_without_invite = true;
        disable_user_create_org = true;
      };

      gerbil = {
        base_endpoint = "152.53.34.16";
      };

      domains = {
        noosphere = {
          base_domain = "noosphere.uk";
          cert_resolver = "letsencrypt";
        };

        keksic = {
          base_domain = "keksic.xyz";
          cert_resolver = "letsencrypt";
        };
      };
    };
  };

  services.imperium.crowdsec.enable = true;

  # systemd.services.traefik.serviceConfig.EnvironmentFile = [
  #   config.clan.core.vars.generators.cloudflare-dns.files."cloudflare-dns.env".path
  # ];

  services.dbus.enable = true;
  users.mutableUsers = false;

  networking.networkmanager.enable = false;
  # networking.useNetworkd = true;
  # systemd.network.enable = true;
  # systemd.network.networks."10-enp3s0" = {
  #   matchConfig.Name = "enp3s0";
  #   address = ["192.168.240.44/24"];
  #   gateway = ["192.168.240.1"];
  # };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22 80 443 51799];
    allowedUDPPorts = [80 443 21820];
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
    helix
    vim
    curl
    htop
  ];
}
