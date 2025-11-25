{
  _class = "clan.service";
  manifest.name = "gaming";
  manifest.readme = "";

  roles.default.description = "Gaming stuff";

  roles.default.perInstance.nixosModule = {
    self,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      self.nixosModules.steam
    ];
    services.imperium.steam.enable = true;

    environment.systemPackages = with pkgs; [
      lutris
      dxvk
      heroic
    ];
  };
}
