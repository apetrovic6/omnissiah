{
  lib,
  config,
  ...
}: let
  flakeCfg = config;
  inherit (lib) mkIf mkMerge mkDefault;
in {
  # flake-parts options (import shared module)
  imports = [../../../../../vars/_noosphere-options.nix];

  # exported NixOS module
  config.flake.nixosModules.noosphere = {lib, ...}: {
    # Import shared noosphere options module
    imports = [../../../../../vars/_noosphere-options.nix];

    # propagate flake values into NixOS config as defaults
    config = mkMerge [
      {
        noosphere.domain = mkDefault flakeCfg.noosphere.domain;
      }

      # pass provider through as a default
      {
        noosphere.sso.provider = mkDefault flakeCfg.noosphere.sso.provider;
      }

      # if url is explicitly set at flake level, pass it through
      (mkIf (flakeCfg.noosphere.sso.url != "") {
        noosphere.sso.url = mkDefault flakeCfg.noosphere.sso.url;
      })

      # wellKnownUrl pass-through
      (mkIf (flakeCfg.noosphere.sso.wellKnownUrl != "") {
        noosphere.sso.wellKnownUrl = mkDefault flakeCfg.noosphere.sso.wellKnownUrl;
      })

      (mkIf (flakeCfg.noosphere.agePublicKey != null) {
        noosphere.agePublicKey = mkDefault flakeCfg.noosphere.agePublicKey;
      })
    ];
  };
}
