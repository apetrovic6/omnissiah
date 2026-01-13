{
  lib,
  config,
  ...
}: let
  flakeCfg = config;

  # Import shared noosphere options (prefixed with _ to avoid import-tree)
  noosphereOptions = import ../../../../../vars/_noosphere-options.nix {inherit lib;};
in {
  # flake-parts options
  options.noosphere = noosphereOptions;

  # exported NixOS module
  config.flake.nixosModules.noosphere = {lib, ...}: let
    inherit (lib) mkIf mkMerge mkDefault;
  in {
    # NixOS options (same definitions, reused)
    options.noosphere = noosphereOptions;

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

      # otherwise derive url from provider + domain
      (mkIf (flakeCfg.noosphere.sso.url == "" && flakeCfg.noosphere.sso.provider != "" && flakeCfg.noosphere.domain != "") {
        noosphere.sso.url = mkDefault "${lib.toLower flakeCfg.noosphere.sso.provider}.${flakeCfg.noosphere.domain}";
      })

      # wellKnownUrl pass-through (or you can derive it similarly if you want)
      (mkIf (flakeCfg.noosphere.sso.wellKnownUrl != "") {
        noosphere.sso.wellKnownUrl = mkDefault flakeCfg.noosphere.sso.wellKnownUrl;
      })

      (mkIf (flakeCfg.noosphere.agePublicKey != null) {
        noosphere.agePublicKey = mkDefault flakeCfg.noosphere.agePublicKey;
      })
    ];
  };
}
