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
      self.nixosModules.pharos
    ];

    environment.systemPackages = [];

    # TODO: Setup services so that they listen on localhost

    # services.imperium.audiobookshelf = {
    #   enable = true;
    #   port = 8008;
    #   group = "media";
    #   openFirewall = false;
    # };

    # services.imperium.tautulli = {
    #   enable = true;
    #   group = "media";
    #   user = "plexpy";
    #   port = 8181;
    # };

    networking.firewall.allowedTCPPorts = [ 80 443 2222 53 22 5380];
    networking.firewall.allowedUDPPorts = [ 80 443 53 ];
    # Or disable the firewall altogether.
    networking.firewall.enable = true;

    # services.imperium.sabnzbd = {
    #   enable = true;
    #   port = 8080;
    #   subdomain = "sab";
    #   group = "media";
    # };

    services.imperium.postgresql = {
      enable = true;
      listenAddresses = "*";
      openFirewall = true;

      authentication = ''
        # TYPE  DATABASE  USER      ADDRESS         METHOD
        local   all       all                       peer
        host    all       all       127.0.0.1/32    scram-sha-256
        host    all       all       ::1/128         scram-sha-256
        host    all       all       192.168.1.0/24  scram-sha-256
      '';

      backup = {
        enable = true;
        location = "/mnt/nas/selfhosted/postgres/backups";
      };

      users.vaultwarden = {
        databases = ["vaultwarden"];
        ensureDBOwnership = true;
      };
    };

    
    services.imperium.technitium-dns-server = {
      enable = true;
      subdomain = "technitium";
      openFirewall = true;
      port = 5380;
    };

    services.imperium.vaultwarden = {
      enable = true;
      port = 8222;
      config = {
        SIGNUPS_ALLOWED = true;
        WEBSOCKET_ENABLED = true;
        WEBSOCKET_ADDRESS = "127.0.0.1";
        WEBSOCKET_PORT = 3012;

        PUSH_ENABLED = false;

        INCOMPLETE_2FA_TIME_LIMIT = 5;

        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_LOG = "critical";
      };

    };

    # services.imperium.ntfy-sh = {
    #   enable = true;
    #   subdomain = "ntfy";
    #   port = 8085;
    # };

    # services.imperium.plex = {
    #   enable = true;
    #   port = 32400; # This is just for Caddy, Plex doesn't expose a port option.
    #   group = "media";
    # };

    # services.imperium.nzbhydra2 = {
    #   enable = true;
    #   subdomain = "nzbhydra";
    #   port = 5076;
    # };

    users.groups.media = {
      gid = 1337;
    };

    # services.imperium.navidrome = {
    #   enable = true;
    #   port = 8888;
    #   group = "media";
    # };

    services.imperium.caddy = {
      enable = true;
      openFirewall = true;
      package = pkgs.caddy.withPlugins {
        plugins = ["github.com/caddy-dns/cloudflare@v0.2.1"];
        hash = "sha256-Zls+5kWd/JSQsmZC4SRQ/WS+pUcRolNaaI7UQoPzJA0=";
      };
    };
  };
}
