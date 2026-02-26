{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;
in {
  imports = [
    self.nixosModules.smb
    self.nixosModules.nfs
    self.nixosModules.postgresql
    self.nixosModules.impermanence
    self.inputs.magos.nixosModules.stylix
    # self.inputs.impermanence.nixosModules.impermanence
    # self.nixosModules.noosphere
    # self.inputs.magos.nixosModules.default
  ];

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

  services.imperium.nfs = {
    enable = true;

    hosts.manjaca = {
      host = "192.168.1.61";

      exports.backup = {
        remotePath = "/volume1/postgres_backup"; # path on the NAS
        mountPoint = "/mnt/nas/postgres_backup";
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
