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

      (mkIf (flakeCfg.noosphere.agePublicKey != null) {
        noosphere.agePublicKey = mkDefault flakeCfg.noosphere.agePublicKey;
      })
    ];
  };
}
