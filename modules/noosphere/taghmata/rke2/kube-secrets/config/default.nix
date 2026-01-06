{
  lib,
  config,
  ...
}: let
  inherit (lib) types mkOption mkIf mkDefault;
in {
  options.noosphere = {
    agePublicKey = mkOption {
      type = types.str;
      description = "AGE public key which will be used to encrypt sops secrets";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain name for the K8S cluster";
    };
  };

  config.flake.nixosModules.noosphere = {lib, ...}: let
    flakeAgeKey = config.noosphere.agePublicKey;
  in {
    options.noosphere.agePublicKey = mkOption {
      type = types.str;
      description = "AGE public key which will be used to encrypt sops secrets";
    };

    options.noosphere.domain = mkOption {
      type = types.str;
      description = "Domain name for the K8S cluster";
    };

    config = mkIf (flakeAgeKey != null) {
      noosphere.agePublicKey = mkDefault flakeAgeKey;
      noosphere.domain = config.noosphere.domain;
    };
  };
}
