# Media libraries: Plex, Tautulli, Immich and Audiobookshelf, and the Intel GPU
# they transcode with.
{
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  boot.kernelModules = ["i915"];

  hardware.graphics.enable = true;

  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    libva-vdpau-driver
  ];

  users.users.audiobookshelf.extraGroups = ["media"];

  services.imperium.audiobookshelf = {
    enable = true;
    port = 8008;
    group = "media";
    openFirewall = false;
    subdomain = "audiobookshelf";
  };

  # The media lives on NFS, but the immich module only orders the server after
  # /var/lib/immich. Without the mount dependency, shutdown can unmount
  # /mnt/nas/photos while immich still holds files there, and the unmount
  # waits on it.
  systemd.services.immich-server.unitConfig.RequiresMountsFor = [
    config.services.imperium.immich.mediaLocation
  ];

  services.imperium.immich = {
    enable = true;

    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;

    database = {
      name = "immich";
      host = "127.0.0.1";
      port = 5432;
    };

    subdomain = "immich";

    user = "immich";
    group = "photos";
    mediaLocation = "/mnt/nas/photos/immich";
    accelerationDevices = ["/dev/dri/renderD128"];
  };

  services.imperium.plex = {
    enable = true;
    port = 32400; # This is just for Caddy, Plex doesn't expose a port option.
    openFirewall = true;
    user = "plex";
    group = "media";
    accelerationDevices = ["*"];
  };

  services.imperium.tautulli = {
    enable = true;
    group = "media";
    user = "plexpy";
    port = 8181;
  };

  users.users.plex.extraGroups = ["media"];

  clan.core.state.audiobookshelf = {
    folders = [
      "/var/lib/audiobookshelf/metadata/backups"
    ];

    preBackupScript = ''
      export PATH=${
        lib.makeBinPath [
          config.systemd.package
        ]
      }

        systemctl stop audiobookshelf.service
    '';

    postBackupScript = ''
        export PATH=${
        lib.makeBinPath [
          config.systemd.package
        ]
      }

      systemctl start audiobookshelf.service
    '';
  };

  users.users.immich.extraGroups = ["photos"];

  users.groups.photos = {
    gid = 65541;
  };

  users.groups.media = {
    gid = 1337;
  };
}
