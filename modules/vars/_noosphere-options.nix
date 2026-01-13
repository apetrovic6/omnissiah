# Shared noosphere option definitions
#
# This file defines the noosphere options once, to be reused across:
# - Flake-parts (global config)
# - NixOS modules (machine config)
# - Nixidy (K8s manifest generation)
#
# Usage:
#   let
#     noosphereOptions = import ../vars/noosphere-options.nix { inherit lib; };
#   in {
#     options.noosphere = noosphereOptions;
#   }
{lib}: let
  inherit (lib) mkOption types;
in {
  agePublicKey = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "AGE public key for SOPS secret encryption";
  };

  domain = mkOption {
    type = types.str;
    default = "";
    description = "Base domain for all services (e.g., noosphere.uk)";
  };

  sso = {
    provider = mkOption {
      type = types.str;
      default = "";
      description = "SSO provider name (e.g., Keycloak)";
    };

    url = mkOption {
      type = types.str;
      default = "";
      description = "SSO provider URL. If empty, derived from provider + domain.";
    };

    wellKnownUrl = mkOption {
      type = types.str;
      default = "";
      description = "OpenID Connect well-known configuration URL";
    };
  };
}
