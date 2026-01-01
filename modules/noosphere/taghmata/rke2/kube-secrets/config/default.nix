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
  };

  config.flake.nixosModules.noosphere = {lib, ...}: let
    flakeAgeKey = config.noosphere.agePublicKey;
  in {
    options.noosphere.agePublicKey = mkOption {
      type = types.str;
      description = "AGE public key which will be used to encrypt sops secrets";
    };

    config = mkIf (flakeAgeKey != null) {
      noosphere.agePublicKey = mkDefault flakeAgeKey;
    };
  };
}
