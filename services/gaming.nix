{
  _class = "clan.service";
  manifest.name = "gaming";
  manifest.readme = "";

  roles.default.description = "Gaming stuff";

  # Single role called "default" (selected by the 'laptop' tag)
  roles.default.perInstance.nixosModule = {
    lib,
    pkgs,
    ...
  }: {
    services.imperium.steam.enable = true;

    environment.systemPackages = with pkgs; = [
      lutris
      dxvk
      heroic
    ];
  };

  #};
}
