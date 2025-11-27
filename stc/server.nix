{config, ...}: {
  _class = "clan.service";
  manifest.name = "server";
  manifest.readme = "";

  roles.default.description = "Server stuff";

  roles.default.perInstance.nixosModule = {
    self,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      self.nixosModules.noosphere
    ];

    environment.systemPackages = [pkgs.cowsay];

    services.imperium.audiobookshelf = {
      enable = true;
      port = 8008;
    };

    networking.firewall.allowedTCPPorts = [80 443 2222 53];
    networking.firewall.allowedUDPPorts = [80 443 53];
    # Or disable the firewall altogether.
    networking.firewall.enable = true;

  users.groups.media = {};

    

    services.imperium.navidrome = {
      enable = true;
      port = 8888;
      openFirewall = true;
      user = "apetrovic";
    };

    services.imperium.caddy = {
      enable = true;

      package = pkgs.caddy.withPlugins {
        plugins = ["github.com/caddy-dns/cloudflare@v0.2.1"];
        hash = "sha256-Dvifm7rRwFfgXfcYvXcPDNlMaoxKd5h4mHEK6kJ+T4A=";
      };
    };
  };
}
