# Shared noosphere options module
#
# This NixOS module defines the noosphere options once, to be reused across:
# - Flake-parts (global config)
# - NixOS modules (machine config)
# - Nixidy (K8s manifest generation)
# - Tofunix (Terraform/OpenTofu)
#
# Usage: Simply import this file in your module imports list.
#   imports = [ path/to/_noosphere-options.nix ];
#
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkIf mkDefault types;
in {
  options.noosphere = {
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

      providerFull = mkOption {
        type = types.str;
        default = "";
        description = "SSO full provider name (e.g., Keycloak)";
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
  };

  # Auto-derive SSO URL from provider + domain if not set
  config = mkIf (config.noosphere.sso.provider != "" && config.noosphere.domain != "") {
    noosphere.sso.url =
      mkDefault
      "${lib.toLower config.noosphere.sso.provider}.${config.noosphere.domain}";
  };
}
