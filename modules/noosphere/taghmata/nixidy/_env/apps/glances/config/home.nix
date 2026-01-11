{
  domain,
  lib,
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
    "immich-app/immich"
    "codeberg:forgejo/forgejo"
    "karakeep-app/karakeep"
    "glanceapp/glance"
    "lukasdietrich/glance-k8s"
    "dockerhub:seerr/seerr"
    "arnarg/nixidy"
    "nix-community/nixhelm"
    "cloudnative-pg/cloudnative-pg"
    "kubernetes-csi/csi-driver-nfs"
  ];

  releases = {
    type = "releases";
    cache = "1d";
    show-source-icon = true;
    inherit repositories;
  };
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

          widgets = [releases];
        }
      ];
    }
  ];
}
