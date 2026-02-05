# Noosphere configuration values - single source of truth
#
# This file contains the actual values used across:
# - flake.nix (flake-parts config)
# - NixOS modules
# - Nixidy (K8s manifests)
# - Tofunix (Terraform/OpenTofu)
#
# For NixOS option definitions, see _noosphere-options.nix
{
  agePublicKey = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
  domain = "noosphere.uk";
  sso = {
    provider = "Keycloak";
    wellKnownUrl = "https://keycloak.noosphere.uk/realms/adeptus-terra/.well-known/openid-configuration";
  };
}
