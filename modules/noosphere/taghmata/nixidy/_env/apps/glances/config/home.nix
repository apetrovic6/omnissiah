{
  domain,
  lib,
  hasGithubToken ? false,
  ...
}: let
  rss = {
    type = "rss";
    cache = "12h";
    limit = 10;
    collapse-after = 3;
    feeds = rssFeeds;
  };

  rssFeeds = [
    {
      url = "https://selfh.st/rss/";
      title = "selfh.st";
    }
  ];

  twitch = {
    type = "twitch-channels";
    channels = ["theprimeagen" "christitustech"];
  };

  news = {
    type = "group";
    widgets = [{type = "hacker-news";} {type = "lobsters";}];
  };

  youtube = {
    type = "videos";
    style = "horizontal-cards";
    collapse-after-rows = 2;
    channels = [
      "UCXuqSBlHAE6Xw-yeJA0Tunw" # Linus Tech Tips
      "UCR-DXc1voovS8nhAvccRZhg" # Jeff Geerling
      "UCsBjURrPoezykLs9EqgamOA" # Fireship
      "UCshObcm-nLhbu8MY50EZ5Ng" # Benn Jordan
      "UC7rzjM9zAfOXRnXV8yKpgsg" # Igor Belan
      "UCoAVMy_9E_n75aZXbotfVjw" # HCL
      "UCJa14zeVf8p6clixTOIOVyQ" # Jakkuh
      "UCylGUf9BvQooEFjgdNudoQg" # The Linux Cast
    ];
  };

  subreddits = ["nixos" "linux" "rust" "kubernetes" "selfhosted" "homelab" "technology" "unixporn"];

  reddit = {
    type = "group";
    widgets =
      lib.map (subreddit: {
        type = "reddit";
        inherit subreddit;
      })
      subreddits;
  };

  # weather = {
  #   type = "weather";
  # };

  repositories = [
    # Application stacks
    "immich-app/immich"                 # ghcr.io/immich-app/immich
    "codeberg:forgejo/forgejo"          # code.forgejo.org/forgejo/forgejo
    "karakeep-app/karakeep"             # ghcr.io/karakeep-app/karakeep
    "glanceapp/glance"                  # docker.io/glanceapp/glance
    "lukasdietrich/glance-k8s"          # ghcr.io/lukasdietrich/glance-k8s/glance-k8s
    "dockerhub:seerr/seerr"             # docker.io/seerr/seerr
    "go-vikunja/vikunja"                # docker.io/vikunja/vikunja (canonical: code.vikunja.io)
    "excalidraw/excalidraw"             # excalidraw/excalidraw
    "meilisearch/meilisearch"           # getmeili/meilisearch

    # Infra / Operators
    "arnarg/nixidy"                     # internal project
    # nix-community/nixhelm publishes no GitHub releases and no git tags (it is
    # a rolling flake), so the releases widget can never resolve it — it would
    # 404 forever and trigger Glance's early-retry loop. Track it with a
    # changedetection widget on commits/master.atom instead, if wanted.
    # "nix-community/nixhelm"
    "cloudnative-pg/cloudnative-pg"     # ghcr.io/cloudnative-pg/cloudnative-pg
    "kubernetes-csi/csi-driver-nfs"     # registry.k8s.io/sig-storage/nfsplugin
    "gitlab:TECHNOFAB/tofunix"          # gitlab.com/TECHNOFAB/tofunix (OpenTofu providers)

    # LinuxServer.io suite (Yarr) — image is lscr.io/linuxserver/<app>,
    # the Dockerfile repos are linuxserver/docker-<app>.
    "linuxserver/docker-lidarr"         # lscr.io/linuxserver/lidarr
    "linuxserver/docker-radarr"         # lscr.io/linuxserver/radarr
    "linuxserver/docker-sonarr"         # lscr.io/linuxserver/sonarr
    "linuxserver/docker-prowlarr"       # lscr.io/linuxserver/prowlarr
    "linuxserver/docker-sabnzbd"        # lscr.io/linuxserver/sabnzbd

    # Storage & Registries
    "goharbor/harbor"                   # docker.io/goharbor/*
    "longhorn/longhorn"                 # docker.io/longhornio/longhorn-*
    "dockerhub:dxflrs/amd64_garage"     # dxflrs/amd64_garage — upstream is git.deuxfleurs.fr (unsupported by glance)
    "rajsinghtech/garage-operator"      # ghcr.io/rajsinghtech/garage-operator
    "dockerhub:noooste/garage-ui"       # noooste/garage-ui — no public repo, tracked by image name

    # Monitoring & Observability
    "prometheus/prometheus"             # quay.io/prometheus/prometheus
    "grafana/grafana"                   # docker.io/grafana/grafana
    "prometheus/node_exporter"          # quay.io/prometheus/node-exporter
    "kiwigrid/k8s-sidecar"              # quay.io/kiwigrid/k8s-sidecar
    "grafana/alloy-operator"            # ghcr.io/grafana/alloy-operator
    "emberstack/kubernetes-reflector"   # docker.io/emberstack/kubernetes-reflector

    # Networking & Security
    "metallb/metallb"                   # quay.io/metallb/*
    "cert-manager/cert-manager"         # quay.io/jetstack/cert-manager-*
    "isindir/sops-secrets-operator"     # quay.io/isindir/sops-secrets-operator
    "dockerhub:searxng/searxng"         # docker.io/searxng/searxng — org publishes no GitHub releases/tags
    "valkey-io/valkey"                  # docker.io/valkey/valkey

    # CI/CD & Auth
    "woodpecker-ci/woodpecker"          # docker.io/woodpeckerci/woodpecker-*
    "pocket-id/pocket-id"               # ghcr.io/pocket-id/pocket-id

    # Misc
    "kalbasit/ncps"                     # ghcr.io/kalbasit/ncps
    "rancher/local-path-provisioner"    # rancher/local-path-provisioner
    "Zenika/alpine-chrome"              # gcr.io/zenika-hub/alpine-chrome
    "jordan-dalby/bytestash"            # ghcr.io/jordan-dalby/bytestash
  ];

  repositoriesOpenTofu = [
    "adyxax/terraform-provider-forgejo"
    "carlpett/terraform-provider-sops"
    "goharbor/terraform-provider-harbor"
  ];

  # Injected from the GLANCE_GITHUB_TOKEN env var (see the glance-secrets
  # SopsSecret). Glance aborts parsing the WHOLE config if a referenced env var
  # is missing, so this attribute is only emitted when the secret is actually
  # wired into the Deployment — never leave `${...}` in the config unguarded.
  githubAuth = lib.optionalAttrs hasGithubToken {
    token = "\${GLANCE_GITHUB_TOKEN}";
  };

  releases = {
    title = "Git";
    type = "releases";
    cache = "1d";
    show-source-icon = true;
    # Without an explicit limit this defaults to 10, so most of the
    # repositories below never render (only the 10 newest releases show).
    limit = 100;
    collapse-after = 10;
    inherit repositories;
  }
  // githubAuth;

  releasesOpenTofu = {
    title = "Open Tofu Providers";
    type = "releases";
    cache = "1d";
    show-source-icon = true;
    repositories = repositoriesOpenTofu;
  }
  // githubAuth;
in {
  home = [
    {
      name = "Home";
      columns = [
        {
          size = "small";
          widgets = [
            {
              type = "calendar";
              first-day-of-the-week = "monday";
            }
            rss
            twitch
          ];
        }

        {
          size = "full";
          widgets = [
            news
            youtube
            reddit
          ];
        }

        {
          size = "small";

          widgets = [releases releasesOpenTofu];
        }
      ];
    }
  ];
}
