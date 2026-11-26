# Aurral: music discovery, requests and a player (with a Subsonic API at
# /rest, which the Aurral Pocket app and other Subsonic clients use).
#
# It keeps everything (SQLite database, settings, users, caches, yt-dlp
# staging) in /config, so that is a ReadWriteOnce Longhorn volume: SQLite must
# not sit on Longhorn's NFS-backed RWX share. Hence also the Recreate
# strategy, so two pods never hold the volume at once.
#
# Albums are requested through the official Lidarr plugin and land in
# Lidarr's root folder, /data/media/music, which Aurral plays from as a
# read-only folder. Single, playlist and flow tracks go to its own library
# folder, /data/media/aurral. Both are on the NAS share mounted at /data, the
# same path as in the *arr apps. The plugin, the read-only folder and the
# download sources are set in the web UI (Settings > Plugins / Library /
# Downloads), not here.
{
  yarr,
  config,
  cartographa,
  ...
}: let
  inherit (yarr) namespace;
  domain = config.noosphere.domain;
  host = "aurral.${domain}";
  port = 3001;
  labels = {app = "aurral";};
in {
  applications.aurral = {
    resources.persistentVolumeClaims.aurral-config = {
      metadata = {
        inherit namespace;
        annotations = {
          "argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";
          "argocd.argoproj.io/sync-wave" = "0";
        };
      };

      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "longhorn";
        # Database plus a 256 MB artwork cache and yt-dlp staging.
        resources.requests.storage = "5Gi";
      };
    };

    resources.deployments.aurral = {
      metadata = {
        inherit namespace labels;
      };

      spec = {
        selector.matchLabels = labels;
        strategy.type = "Recreate";
      };

      spec.template = {
        metadata = {inherit labels;};

        spec.volumes = [
          {
            name = "config";
            persistentVolumeClaim.claimName = "aurral-config";
          }
          {
            name = "data";
            nfs = {
              server = cartographa.hosts.manjaca;
              path = "/volume1/data/";
            };
          }
        ];

        spec.containers = [
          {
            name = "aurral";
            image = "ghcr.io/lklynet/aurral:latest";

            volumeMounts = [
              {
                name = "config";
                mountPath = "/config";
              }
              {
                name = "data";
                mountPath = "/data";
              }
            ];

            env = [
              # The entrypoint starts as root, chowns /config and drops to
              # these, the owner of the media share as in the *arr apps.
              {
                name = "PUID";
                value = "1031";
              }
              {
                name = "PGID";
                value = "65537";
              }
              {
                name = "LIBRARY_FOLDER";
                value = "/data/media/aurral";
              }
              {
                name = "FILE_BROWSE_ROOTS";
                value = "/data/media";
              }
              {
                name = "AURRAL_PUBLIC_URL";
                value = "https://${host}";
              }

              # Sign-in through Pocket ID, next to the local accounts. The
              # client and its aurral-oidc Secret come from tofunix
              # (_tofunix/pharos/clients.nix). Aurral sets the role on every
              # SSO login from the groups claim, so Pocket ID's Admin group
              # is what makes an Aurral admin.
              {
                name = "OIDC_ENABLED";
                value = "true";
              }
              {
                name = "OIDC_ISSUER";
                value = "https://id.${domain}";
              }
              {
                name = "OIDC_REDIRECT_URI";
                value = "https://${host}/sso/callback";
              }
              {
                name = "OIDC_SCOPES";
                value = "openid profile email groups";
              }
              {
                name = "OIDC_GROUPS_CLAIM";
                value = "groups";
              }
              {
                name = "OIDC_ADMIN_GROUPS";
                value = "Admin";
              }
            ];

            # OIDC_CLIENT_ID and OIDC_CLIENT_SECRET.
            envFrom = [{secretRef.name = "aurral-oidc";}];

            ports = [{containerPort = port;}];
          }
        ];
      };
    };

    resources.services.aurral = {
      metadata = {
        inherit namespace;
      };

      spec = {
        type = "ClusterIP";
        selector = labels;
        ports = [
          {
            protocol = "TCP";
            port = 80;
            targetPort = port;
          }
        ];
      };
    };

    ingresses.aurral-ip-root = {
      inherit namespace host;
      service = "aurral";
      port = 80;
      tlsSecret = "aurral-tls";
      protect = true;
      glance = {
        name = "Aurral";
        icon = "di:aurral";
        description = "Music discovery and player";
        id = "aurral";
        parent = "aurral";
        category = "yarr";
      };
    };
  };
}
