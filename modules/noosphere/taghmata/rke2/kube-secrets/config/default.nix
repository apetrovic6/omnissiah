{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types;

  flakeCfg = config;

  # Define the option set ONCE, reuse in both module systems
  noosphereOptions = {
    agePublicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "AGE public key which will be used to encrypt sops secrets";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain name for the K8S cluster";
    };

    sso = {
      provider = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Base domain used by nixidy modules.";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Base domain used by nixidy modules.";
      };

      wellKnownUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Well known URL endpoint";
      };
    };
  };
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
