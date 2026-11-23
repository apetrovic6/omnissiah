# forge.ugalabugala.org, the cerberus forge. The product repositories on it
# are declared by ../fabricata.nix; this file holds the rest.
#
# omnissiah, this repository, is not created here; only what its CI needs is
# managed.
{
  config,
  lib,
  ref,
  vars,
  ...
}: let
  inherit (config.scriptorium) owner;
  bot = "hermes";
  # Keep the grant explicit; a new product must not inherit Hermes access.
  repos = {
    rust-app-template = {
      name = "rust-app-template";
      branch = "master";
      # Preserve the template's existing PR checks when adopting its rule.
      checks = [
        "ci / ci-pure (pull_request)"
        "ci / ci-impure (pull_request)"
        "ci / ci-android (pull_request)"
      ];
    };
    pilot = {
      inherit (ref.forgejo_repository.pilot) name;
      branch = ref.forgejo_repository.pilot.default_branch;
      checks = [];
    };
  };
  publicKey = vars.machine "stygies" "hermes-forgejo-ssh" "id_ed25519.pub";
in {
  reliquary.ntfy_access = {
    generator = "ntfy-access";
    file = "alertmanager-ntfy";
  };

  # NTFY_TOKEN lets the Machines workflow announce the "render manifests" pull
  # request (rituals/render-manifests-pr.sh) on ntfy. It is the publisher token
  # of the `ntfy-access` clan var (taghmata/reliquary/ntfy): write-only on the
  # homelab-alerts topic, the same credential Alertmanager publishes with. Read
  # from the var, so rotating the var and applying again updates the secret and
  # nothing is copied by hand.
  resource.forgejo_repository_actions_secret.omnissiah-ntfy-token = {
    provider = "forgejo.cerberus";
    inherit (config.scriptorium) owner;
    repository = "omnissiah";
    name = "NTFY_TOKEN";
    # The var is a SopsSecret manifest; the token is in its one secret template.
    data = "\${yamldecode(data.sops_file.ntfy_access.raw).spec.secretTemplates[0].stringData.token}";
  };

  # The configuration can render before stygies is enrolled. A plan still
  # requires the public key, so missing vars cannot schedule its removal.
  variable.hermes_forgejo_public_key =
    {
      type = "string";
      nullable = false;
      description = "The public stygies hermes-forgejo-ssh Clan var.";
    }
    // lib.optionalAttrs (builtins.pathExists publicKey) {
      default = lib.trim (builtins.readFile publicKey);
    };

  resource.gitea_public_key.hermes = {
    provider = "gitea.cerberus";
    username = bot;
    title = "hermes@stygies";
    key = ref.var.hermes_forgejo_public_key;
    read_only = false;
  };

  resource.gitea_repository_collaborator = lib.mapAttrs' (name: repo:
    lib.nameValuePair "${name}-hermes" {
      provider = "gitea.cerberus";
      # Protect the default branch before granting push access.
      depends_on = ["gitea_repository_branch_protection.${name}"];
      inherit owner;
      repo = repo.name;
      username = bot;
      permission = "write";
    })
  repos;

  resource.gitea_repository_branch_protection =
    lib.mapAttrs (_: repo: {
      provider = "gitea.cerberus";
      inherit (repo) name;
      username = owner;
      rule_name = repo.branch;
      enable_push = false;
      merge_whitelist_users = [owner];
      required_approvals = 0;
      status_check_patterns = repo.checks;
    })
    repos;
}
