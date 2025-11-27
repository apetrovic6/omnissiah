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
    # self.inputs.magos.nixosModules.default
  ];

  # magos.stylix.enable = false;

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
  
  
  services.imperium.smb.hosts.manjaca = {
    host = "192.168.1.61";
    credentialsVarName = "manjaca-nas-credentials";

    shares.data = {
      mountPoint = "/mnt/nas/data";
    };

    shares.docker = {
      mountPoint = "/mnt/nas/docker";
    };

    shares.selfhosted = {
      mountPoint = "/mnt/nas/selfhosted";
    };
  };

  services.dbus.enable = true;
}
