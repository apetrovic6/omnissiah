# Noosphere options for nixidy module graph
#
# This module provides the noosphere options (domain, SSO) to nixidy
# application definitions via config.noosphere.*
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkIf mkDefault;

  # Import shared noosphere options (prefixed with _ to avoid import-tree)
  noosphereOptions = import ../../../../vars/_noosphere-options.nix {inherit lib;};
in {
  options.noosphere = noosphereOptions;

  # Auto-derive SSO URL from provider + domain if not set
  config = mkIf (config.noosphere.sso.provider != "" && config.noosphere.domain != "") {
    noosphere.sso.url =
      mkDefault
      "${lib.toLower config.noosphere.sso.provider}.${config.noosphere.domain}";
  };
}
