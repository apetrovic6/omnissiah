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

    nixpkgs.overlays = [
      (_final: prev: let
        stable = import self.inputs.nixpkgs-stable {
          inherit (prev.stdenv.hostPlatform) system;
          config.allowUnfree = true;
        };
      in {
        inherit (stable) bubblewrap;
      })
    ];

    services.imperium.steam.enable = true;

    environment.systemPackages = with pkgs; [
      lutris
      dxvk
      heroic
    ];
  };
}
