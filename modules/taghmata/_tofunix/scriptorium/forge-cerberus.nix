# forge.ugalabugala.org, the cerberus forge. The product repositories on it
# are declared by ../fabricata.nix; this file holds the rest.
#
# omnissiah, this repository, is not created here; only what its CI needs is
# managed.
{
  config,
  lib,
  ref,
  relic,
  vars,
  ...
}: let
  inherit (config.scriptorium) owner;
  bot = "hermes";
  # Keep the grant explicit; a new product must not inherit Hermes access.
  # Adding a repo here is all it takes: a read grant, its branch rule, a fork
  # under hermes, and one more allowed repo for the bot. Its runtime token
  # (All repositories) reaches the new pair without changes. Set
  # `protect = false` to skip the branch rule; `branch`, `directPush` and
  # `checks` are then unused.
  repos = {
    # omnissiah = {
    #   name = "omnissiah";
    #   # No branch rule: manjo and the scheduled flake.lock job push master
    #   # directly, and no workflow runs on pull_request. Hermes only reads it
    #   # and pushes to its fork.
    #   protect = false;
    # };
    rust-app-template = {
      name = "rust-app-template";
      branch = "master";
      # Changes reach master only through PRs, as before the rule was adopted:
      # no direct pushes, not even from the owner.
      directPush = false;
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
      # pilot had no rule before; the owner keeps pushing to master directly.
      directPush = true;
      checks = [];
    };
  };
  passwordCredential = "tofunix-hermes-forgejo-password";
  manageBot = builtins.pathExists (vars.shared passwordCredential passwordCredential);
  publicKey = vars.machine "stygies" "hermes-forgejo-ssh" "id_ed25519.pub";
  manageKey = manageBot && builtins.pathExists publicKey;
  forkCredential = "tofunix-hermes-forgejo-forks";
  manageForks = manageBot && builtins.pathExists (vars.shared forkCredential forkCredential);

  # advisory-bot opens the template's nightly advisory pull requests from its
  # own fork (rust-app-template RT-122), so it can read the base repository but
  # not write it. A write collaborator outside the trusted-CI users makes every
  # master run untrusted (HOM-32). The read grant applies without the
  # credential; the fork and the job's secret wait for it.
  advisoryBot = "advisory-bot";
  advisoryRepo = repos.rust-app-template.name;
  advisoryCredential = "tofunix-advisory-bot-forgejo";
  manageAdvisory = builtins.pathExists (vars.shared advisoryCredential advisoryCredential);
in {
  reliquary.ntfy_access = {
    generator = "ntfy-access";
    file = "alertmanager-ntfy";
  };

  # Unrelated plans must still work before the bot password is generated.
  reliquary.hermes_password = lib.mkIf manageBot {
    generator = passwordCredential;
  };

  resource.gitea_user = lib.optionalAttrs manageBot {
    hermes = {
      provider = "gitea.cerberus";
      username = bot;
      login_name = bot;
      email = "hermes@forge.ugalabugala.org";
      password = relic "hermes_password" "password";
      restricted = true;
      admin = false;
      active = true;
      # One fork per repo in `repos`, so adding a repo there is all it takes.
      max_repo_creation = builtins.length (builtins.attrNames repos);
      allow_create_organization = false;
      allow_git_hook = false;
      allow_import_local = false;
      send_notification = false;
      must_change_password = false;
      # Forgejo never returns passwords; the provider only sets this on create.
      lifecycle.ignore_changes = ["password"];
    };
  };

  # Gitea forks into the authenticated user's namespace, not the upstream
  # owner's. Keep the operator token separate from the token on Stygies.
  reliquary.hermes_fork_secrets = lib.mkIf manageForks {
    generator = forkCredential;
  };
  provider.gitea.hermes = lib.mkIf manageForks {
    inherit (config.provider.gitea.cerberus) base_url;
    token = relic "hermes_fork_secrets" "forgejo_token";
  };

  # One PAT for both of advisory-bot's jobs: forking here, and pushing to the
  # fork and opening the pull request in the nightly. It needs the same power
  # for both.
  reliquary.advisory_bot_secrets = lib.mkIf manageAdvisory {
    generator = advisoryCredential;
  };
  provider.gitea.advisory = lib.mkIf manageAdvisory {
    inherit (config.provider.gitea.cerberus) base_url;
    token = relic "advisory_bot_secrets" "forgejo_token";
  };

  resource.forgejo_repository_actions_secret."${advisoryRepo}-advisory-pr-token" = lib.mkIf manageAdvisory {
    provider = "forgejo.cerberus";
    inherit owner;
    repository = advisoryRepo;
    name = "ADVISORY_PR_TOKEN";
    data = relic "advisory_bot_secrets" "forgejo_token";
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

  # The public key is absent until stygies has generated its Clan vars.
  variable = lib.optionalAttrs manageKey {
    hermes_forgejo_public_key = {
      type = "string";
      nullable = false;
      description = "The public stygies hermes-forgejo-ssh Clan var.";
      default = lib.trim (builtins.readFile publicKey);
    };
  };

  resource.gitea_public_key = lib.optionalAttrs manageKey {
    hermes = {
      provider = "gitea.cerberus";
      inherit (ref.gitea_user.hermes) username;
      title = "hermes@stygies";
      key = ref.var.hermes_forgejo_public_key;
      read_only = false;
    };
  };

  resource.gitea_repository_collaborator =
    lib.optionalAttrs manageBot (
      lib.mapAttrs' (name: repo:
        lib.nameValuePair "${name}-hermes" {
          provider = "gitea.cerberus";
          # Keep the default branch protected before admitting the bot.
          depends_on = lib.optional (repo.protect or true) "gitea_repository_branch_protection.${name}";
          inherit owner;
          repo = repo.name;
          inherit (ref.gitea_user.hermes) username;
          permission = "read";
        })
      repos
    )
    // {
      # Already a collaborator (with write); creating this downgrades it in place.
      "${advisoryRepo}-advisory-bot" = {
        provider = "gitea.cerberus";
        depends_on = ["gitea_repository_branch_protection.${advisoryRepo}"];
        inherit owner;
        repo = advisoryRepo;
        username = advisoryBot;
        permission = "read";
      };
    };

  # Omit the alias and resources together before enrollment. If the credential
  # is later removed, OpenTofu cannot delete stateful forks via another alias.
  resource.gitea_fork =
    lib.optionalAttrs manageForks (
      lib.mapAttrs (name: repo: {
        provider = "gitea.hermes";
        depends_on = ["gitea_repository_collaborator.${name}-hermes"];
        inherit owner;
        repo = repo.name;
        lifecycle.prevent_destroy = true;
      })
      repos
    )
    // lib.optionalAttrs manageAdvisory {
      "${advisoryRepo}-advisory-bot" = {
        provider = "gitea.advisory";
        depends_on = ["gitea_repository_collaborator.${advisoryRepo}-advisory-bot"];
        inherit owner;
        repo = advisoryRepo;
        lifecycle.prevent_destroy = true;
      };
    };

  resource.gitea_repository_branch_protection =
    lib.mapAttrs (_: repo: {
      provider = "gitea.cerberus";
      inherit (repo) name;
      username = owner;
      rule_name = repo.branch;
      # Forgejo's CanUserPush denies even the owner when pushes are disabled,
      # so a repo that keeps direct pushes allows them for the owner only.
      # Hermes never needs them: it has read access and pushes to its forks.
      enable_push = repo.directPush;
      push_whitelist_users = lib.optional repo.directPush owner;
      merge_whitelist_users = [owner];
      required_approvals = 0;
      status_check_patterns = repo.checks;
    })
    (lib.filterAttrs (_: repo: repo.protect or true) repos);
}
