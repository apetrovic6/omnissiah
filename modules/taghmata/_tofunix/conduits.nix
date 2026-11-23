# Conduits: every provider, and the relic (./patterns/reliquary.nix) holding
# the credential it logs in with. The state bucket's own credentials are not
# here; .envrc exports them from the `tofunix-s3-secrets` var.
{
  noosphere,
  relic,
  ...
}: let
  inherit (noosphere) domain;
  inherit (import ../../cartographa/_cartographa.nix) lab;
in {
  reliquary = {
    forgejo_secrets.generator = "tofunix-forgejo-secret";
    forgejo_nix_secrets.generator = "tofunix-forgejo-nix-secret";
    github_secrets.generator = "tofunix-github-secret";
    secrets.generator = "tofunix-harbor-secrets";
    pocket_api_key.generator = "tofunix-pocketid-secret";
    proxmox_secrets.generator = "tofunix-proxmox-secret";
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
      base_uri = "https://forge.${lab.domain}";
      api_token = relic "forgejo_nix_secrets" "forgejo_token";
    };

    # These endpoints are not exposed by the pinned Forgejo provider.
    gitea.cerberus = {
      base_url = "https://forge.${lab.domain}";
      token = relic "forgejo_nix_secrets" "forgejo_token";
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

    # The Proxmox host mars runs on. API token only: nothing here needs the
    # provider's SSH access (no snippets, no disk imports). Self-signed cert.
    # The token ID is not secret; the var holds only the UUID secret.
    proxmox.default = {
      endpoint = "https://192.168.1.11:8006/";
      api_token = "tofu@pam!tofunix=${relic "proxmox_secrets" "api_token"}";
      insecure = true;
    };

    # taghmata, for the Secrets that hand OIDC credentials to the apps. The
    # context is named because the workstation's current one is not taghmata.
    kubernetes.default = {
      config_path = "~/.kube/config";
      config_context = "default";
    };
  };
}
