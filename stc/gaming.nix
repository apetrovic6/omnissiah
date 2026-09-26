{
  _class = "clan.service";
  manifest.name = "gaming";
  manifest.readme = "";

  roles.default.description = "Gaming stuff";

  roles.default.perInstance.nixosModule = {
    self,
    lib,
    pkgs,
    config,
    ...
  }: {
    imports = [
      self.nixosModules.steam
      self.nixosModules.rocksmith
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

    # PipeASIO (from nixos-rocksmith) builds against Wine's MSVC cross-
    # compiler, which requires accepting the Microsoft VS license terms.
    nixpkgs.config.microsoftVisualStudioLicenseAccepted = true;

    services.imperium.steam.enable = true;

    environment.systemPackages = with pkgs; [
      lutris
      dxvk
      heroic
    ];
  };
}
