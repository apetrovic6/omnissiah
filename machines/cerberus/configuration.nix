{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
in {
  imports = [
    self.nixosModules.smb
    self.nixosModules.postgresql
    self.nixosModules.impermanence
    self.inputs.magos.nixosModules.stylix
    # self.inputs.impermanence.nixosModules.impermanence
    # self.nixosModules.noosphere
    # self.inputs.magos.nixosModules.default
  ];

  services.qemuGuest.enable = true;

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
