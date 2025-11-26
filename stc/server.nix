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
        self.nixosModules.noosphere.audiobookshelf
      ];


      services.imperium.audiobookshelf = {
        enable = true;
        port = 8008;
      };
    };
}
