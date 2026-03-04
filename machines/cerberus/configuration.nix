{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;
  baseDomain = config.clan.core.vars.generators."caddy-env".files."domain".value;
in {
  imports = [
    self.nixosModules.smb
    self.nixosModules.nfs
    self.nixosModules.postgresql
    self.nixosModules.scriptorium
    self.nixosModules.impermanence
    self.inputs.magos.nixosModules.stylix
    # self.inputs.impermanence.nixosModules.impermanence
    # self.nixosModules.noosphere
    # self.inputs.magos.nixosModules.default
  ];

  nixpkgs.overlays = [ self.overlays.newt ];

  services.qemuGuest.enable = true;

  services.caddy.virtualHosts = {
    "${mkDomain "syn"}" = {
      extraConfig = mkRevProxyVHost {
        port = 5000;
        host = "192.168.1.61";
      };
    };
  };

  services.caddy.virtualHosts = {
    "${mkDomain "proxmox"}" = {
      extraConfig = ''
        reverse_proxy "https://192.168.1.10:8006" {
          transport http {
            tls_insecure_skip_verify
          }
        }
        tls {
          dns cloudflare {$CLOUDFLARE_API_TOKEN}
        }
      '';
    };
  };

  services.newt = {
    enable = true;
    # package = newtOverride;
    settings.endpoint = "https://ugalabugala.org";
    environmentFile = config.clan.core.vars.generators.newt.files."newt.env".path;

    blueprint = {
      public-resources = {
        
      };

      private-resources = {
        ugala-bugala = {
          name = "Ugala Bugala";
          mode = "host";
          destination = "192.168.1.191";
          alias = "*.ugalabugala.org";
          site = "noosphere";
          disable-icmp = true;
          tcp-ports = "80,443,53";
          udp-ports = "53";
        };

         keksic = {
          name = "Keksic";
          mode = "host";
          destination = "192.168.1.243";
          alias = "*.keksic.xyz";
          site = "noosphere";
          disable-icmp = true;
          tcp-ports = "80,443";
          udp-ports = "";
        };

        noosphere = {
          name = "Noosphere";
          mode = "host";
          destination = "192.168.1.240";
          alias = "*.noosphere.uk";
          site = "noosphere";
          disable-icmp = true;
          tcp-ports = "80,443";
          udp-ports = "";
        };

        technitium = {
          name = "Technitium";
          mode = "host";
          destination = "192.168.1.191";
          site = "noosphere";
          disable-icmp = true;
          tcp-ports = "53";
          udp-ports = "53";
        };

      };
    };
  };

  clan.core.vars.generators.newt = {
    files."newt.env" = {
      secret = true;
      mode = "0400";
    };

    prompts.id = {
      description = "Newt client ID from Pangolin dashboard";
      type = "hidden";
      persist = true;
    };

    prompts.secret = {
      description = "Newt client secret from Pangolin dashboard";
      type = "hidden";
      persist = true;
    };

    runtimeInputs = [pkgs.coreutils];

    script = ''
      set -euo pipefail
      id="$(cat "$prompts/id")"
      secret="$(cat "$prompts/secret")"

      cat > "$out/newt.env" <<EOF
NEWT_ID=$id
NEWT_SECRET=$secret
EOF
    '';
  };

  services.imperium.nfs = let
    serverRoot = "/mnt/nas";
  in {
    enable = true;

    hosts.manjaca = let
      nasRoot = "/volume1";
    in {
      host = "192.168.1.61";

      exports.backup = {
        remotePath = "${nasRoot}/postgres_backup"; # path on the NAS
        mountPoint = "${serverRoot}/postgres_backup";
      };

      exports.git = {
        remotePath = "${nasRoot}/git";
        mountPoint = "${serverRoot}/git";
        nfsVersion = "3";
        extraOptions = ["nolock"];
      };

      # exports.media = {
      #   remotePath = "/volume1/media";
      #   mountPoint = "/mnt/nas/media";
      # };

      # exports.selfhosted = {
      #   remotePath = "/volume1/selfhosted";
      #   mountPoint = "/mnt/nas/selfhosted";
      # };
    };
  };

  users.users.postgres.extraGroups = ["backup"];
  users.groups.backup = {
    gid = 65539;
  };

  # nix = {
  #   extraOptions = ''
  #     !include ${config.clan.core.vars.generators.attic-pull-token.files.token.path}
  #     netrc-file = /home/apetrovic/.config/nix/netrc
  #   '';

  #   settings = {
  #     trusted-public-keys = [
  #       "manjo:NYye+6m7jUVm3d9GUoIjXeX55/sz9xnRP/gl8THza6k="
  #     ];
  #   };
  # };
  #

  services.imperium.smb.enable = true;

  users.users.forgejo.extraGroups = ["git"];
  users.groups.git = {
    gid = 65540;
  };

  services.imperium.forgejo = {
    enable = true;

    user = "forgejo";
    group = "git";

    stateDir = "/mnt/nas/git";

    port = 9000;
    host = "127.0.0.1";
    subdomain = "forge";
    domain = baseDomain;

    sshPort = 2222;
    startSshServer = true;

    database = {
      host = "127.0.0.1";
      name = "forgejo";
      user = "forgejo";
    };

    sso = {
      enable = true;
      providerName = "Pocket ID";
      autoDiscoverUrl = "https://id.noosphere.uk/.well-known/openid-configuration";
    };
  };

  services.imperium.impermanence = {
    enable = false; # TODO: Setup impermanence
  };

  # environment.persistence."/persist" = {
  #   enable = false;
  #   directories = [
  #     "/etc"
  #     "/var/spool"
  #     "/root"
  #     "/srv"
  #     "/var/lib/nixos"
  #     "/var/db/sudo/lectured"
  #     "/var/lib/systemd/coredump"
  #     "/etc/NetworkManager/system-connections"
  #   ];
  # };

  users.groups.media = {
    gid = 1337;
  };

  # services.xserver.videoDrivers = [ "intel" ];
  # hardware.enableAllFirmware = true;

  # services.xserver.videoDrivers = [ "intel" ];
  # hardware.intel-gpu-tools.enable = true;
  # boot.kernelModules = [ "i915" ];

  services.imperium.smb.hosts.manjaca = {
    host = "192.168.1.61";
    credentialsVarName = "manjaca-nas-credentials";

    shares.data = {
      mountPoint = "/mnt/nas/data";
      gid = 1337;
    };

    # shares.docker = {
    #   mountPoint = "/mnt/nas/docker";
    # };

    shares.selfhosted = {
      mountPoint = "/mnt/nas/selfhosted";
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

  services.openssh = {
    enable = true;
    ports = [22];
    settings = {
      PasswordAuthentication = false;
    };
  };

  services.dbus.enable = true;
}
