# Conduits: every provider, and the relic (./patterns/reliquary.nix) holding
# the credential it logs in with. The state bucket's own credentials are not
# here; .envrc exports them from the `tofunix-s3-secrets` var.
{
  noosphere,
  relic,
  ...
}: let
  inherit (noosphere) domain;
in {
  reliquary = {
    forgejo_secrets.generator = "tofunix-forgejo-secret";
    forgejo_nix_secrets.generator = "tofunix-forgejo-nix-secret";
    github_secrets.generator = "tofunix-github-secret";
    codeberg_secrets.generator = "tofunix-codeberg-secret";
    secrets.generator = "tofunix-harbor-secrets";
    pocket_api_key.generator = "tofunix-pocketid-secret";
  };

  # Where the cluster forge mirrors to, with one account token per host
  # (./patterns/repos.nix: `mirrorTo`).
  scriptorium.remotes = {
    github = {
      url = "https://github.com/apetrovic6";
      username = "apetrovic6";
      token = relic "github_secrets" "github_token";
    };
    # No provider below: the Codeberg repositories are created by hand.
    codeberg = {
      url = "https://codeberg.org/apetrovic";
      username = "apetrovic";
      token = relic "codeberg_secrets" "codeberg_token";
    };
  };

  provider = {
    # Decrypts the relics.
    sops.default = {};

    # The cluster forge, forge.noosphere.uk. The default forgejo provider.
    forgejo.default = {
      base_uri = "https://forge.${domain}";
      api_token = relic "forgejo_secrets" "forgejo_token";
    };

    # The cerberus forge, forge.ugalabugala.org, where this repository and the
    # rust-app-template products live. Resources select it with
    # `provider = "forgejo.cerberus"`.
    forgejo.cerberus = {
      base_uri = "https://forge.ugalabugala.org";
      api_token = relic "forgejo_nix_secrets" "forgejo_token";
    };

    # Mirror repositories under github.com/apetrovic6.
    github.default = {
      owner = "apetrovic6";
      token = relic "github_secrets" "github_token";
    };

    harbor.default = {
      url = "https://harbor.${domain}";
      username = relic "secrets" "harbor_username";
      password = relic "secrets" "harbor_password";
    };

    pocketid.default = {
      base_url = "https://id.${domain}";
      api_token = relic "pocket_api_key" "api_key";
    };

    # taghmata, for the Secrets that hand OIDC credentials to the apps. The
    # context is named because the workstation's current one is not taghmata.
    kubernetes.default = {
      config_path = "~/.kube/config";
      config_context = "default";
    };
  };
}
