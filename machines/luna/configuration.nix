{
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    self.nixosModules.smb
    self.nixosModules.impermanence
    # self.inputs.impermanence.nixosModules.impermanence
    # self.inputs.magos.nixosModules.default
  ];

networking.interfaces.enp1s0 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.1.232";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = {
    address = "192.168.1.1";
    interface = "enp1s0";
  };
  networking.nameservers = [ "192.168.1.105" ];

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

  services.imperium.smb.enable = false;

  services.imperium.impermanence = {
    enable = false; # TODO: Setup impermanence
  };

  environment.persistence."/persist" = {
    enable = false;
    directories = [
      "/etc"
      "/var/spool"
      "/root"
      "/srv"
      "/var/lib/nixos"
      "/var/db/sudo/lectured"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
    ];
  };

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

    # shares.selfhosted = {
    #   mountPoint = "/mnt/nas/selfhosted";
    # };
  };

  services.dbus.enable = true;
}
