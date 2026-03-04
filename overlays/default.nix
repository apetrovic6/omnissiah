{ ... }: {
  flake.overlays.pangolin-cli = final: prev: {
    pangolin-cli = prev.pangolin-cli.overrideAttrs (old: {
      version = "0.5.1";
      src = old.src.override {
        hash = "sha256-+WwCYWC3CBvPnoakwD7rKJHckT5g4pUbtci/zRhGPFs=";
      };
      vendorHash = "sha256-gj7c8kMIX+xrGeoJjRQkPZdLuQuri2wAR0rXE2APCd8=";
      doInstallCheck = false; # upstream 0.5.1 tag has version const still set to 0.5.0
    });
  };
}
