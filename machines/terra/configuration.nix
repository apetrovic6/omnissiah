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
    self.inputs.magos.nixosModules.stylix
    self.nixosModules.noosphere
    # self.inputs.impermanence.nixosModules.impermanence
    # self.inputs.magos.nixosModules.default
  ];

  # Sets the private key secret for sops secrets operator in the cluster
  noosphere.taghmata.sopsAgeKey.enable = true;

networking.interfaces.enp1s0 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.1.138";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = {
    address = "192.168.1.1";
    interface = "enp1s0";
  };
  networking.nameservers = [ "192.168.1.105" ]; 

  magos.stylix = {
    enable = true;
    image = ../../wallpapers/lofi/17.png;
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

  # Longhorn's trimFilesystem API hardcodes /usr/bin/fstrim, which doesn't
  # exist on NixOS. This symlink makes it available so Longhorn can trim
  # volumes to reclaim freed space from the block device.
  system.activationScripts.fstrim-link = ''
    mkdir -p /usr/bin
    ln -sf /run/current-system/sw/bin/fstrim /usr/bin/fstrim
  '';
}
