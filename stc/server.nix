{...}: {
  _class = "clan.service";
  manifest.name = "server";
  manifest.readme = "";

  roles.default.description = "Server stuff";

  roles.default.perInstance.nixosModule = {
    self,
    pkgs,
    ...
  }: {
    imports = [
      self.nixosModules.noosphere
    ];

    environment.systemPackages = [pkgs.cowsay];

    # TODO: Setup services so that they listen on localhost

    services.imperium.audiobookshelf = {
      enable = true;
      port = 8008;
      group = "media";
      openFirewall = false;
    };

    services.imperium.tautulli = {
      enable = true;
      group = "media";
      user = "plexpy";
      port = 8181;
    };

    services.imperium.searx = {
      enable = true;
      package = pkgs.searxng;
      port = 9012;
    };

    networking.firewall.allowedTCPPorts = [80 443 2222 53];
    networking.firewall.allowedUDPPorts = [80 443 53];
    # Or disable the firewall altogether.
    networking.firewall.enable = true;

    services.imperium.ntfy-sh = {
      enable = true;
      subdomain = "ntfy";
      port = 8085;
    };

    services.imperium.plex = {
      enable = true;
      port = 32400; # This is just for Caddy, Plex doesn't expose a port option.
      group = "media";
    };

    services.imperium.nzbhydra2 = {
      enable = true;
      subdomain = "nzbhydra";
      port = 5076;
    };

    users.groups.media = {
      gid = 1337;
    };

    services.imperium.navidrome = {
      enable = true;
      port = 8888;
      group = "media";
    };

    services.imperium.caddy = {
      enable = true;
      openFirewall = true;
      package = pkgs.caddy.withPlugins {
        plugins = ["github.com/caddy-dns/cloudflare@v0.2.1"];
        hash = "sha256-Dvifm7rRwFfgXfcYvXcPDNlMaoxKd5h4mHEK6kJ+T4A=";
      };
    };
  };
}
