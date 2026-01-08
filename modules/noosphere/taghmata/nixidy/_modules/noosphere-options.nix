# ./nixidy/options/noosphere.nix
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkIf mkDefault types;
in {
  options.noosphere = {
    domain = mkOption {
      type = types.str;
      default = "";
    };

    sso.provider = mkOption {
      type = types.str;
      default = "";
    };

    sso.url = mkOption {
      type = types.str;
      default = "";
    };
  };

  config = mkIf (config.noosphere.sso.provider != "" && config.noosphere.domain != "") {
    noosphere.sso.url =
      mkDefault
      "${lib.toLower config.noosphere.sso.provider}.${config.noosphere.domain}";
  };
}
