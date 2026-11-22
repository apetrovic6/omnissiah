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

    # Disabled 2026-11-22: pinning bubblewrap system-wide changed the hash of
    # xdg-desktop-portal/flatpak, so they built from source (no cache hit) and
    # xdg-desktop-portal's flaky D-Bus tests failed the build. If Steam needs
    # the old bubblewrap again, scope it via steam.override { buildFHSEnv = ...; }.
    # nixpkgs.overlays = [
    #   (_final: prev: let
    #     stable = import self.inputs.nixpkgs-stable {
    #       inherit (prev.stdenv.hostPlatform) system;
    #       config.allowUnfree = true;
    #     };
    #   in {
    #     inherit (stable) bubblewrap;
    #   })
    # ];

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
