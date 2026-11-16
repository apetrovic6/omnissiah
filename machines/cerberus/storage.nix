# Mounts from the Synology NAS (manjaca), over NFS and SMB.
{
  self,
  lib,
  ...
}: {
  services.imperium.nfs = let
    serverRoot = "/mnt/nas";
  in {
    enable = true;

    hosts.manjaca = let
      nasRoot = "/volume1";
    in {
      host = self.lib.hosts.manjaca;

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

      exports.photos = {
        remotePath = "${nasRoot}/photos";
        mountPoint = "${serverRoot}/photos";
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

  services.imperium.smb.enable = true;

  services.imperium.smb.hosts.manjaca = {
    host = self.lib.hosts.manjaca;
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
}
