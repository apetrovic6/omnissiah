{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
  };
}
