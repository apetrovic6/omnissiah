{lib, ...}: let
  inherit (lib) mkOption types;
in {
  options.noosphere = {
    domain = mkOption {
      type = types.str;
      description = "Base domain for cluster apps.";
    };
  };
}
