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
    #   # Its master rule is the standalone one at the end of this file, so
    #   # Hermes gets nothing there. Enrolling it here means moving that rule
    #   # in: branch = "master"; directPush = true; checks = [];
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

  # ci-bot opens omnissiah's CI pull requests (flake.lock, rendered
  # manifests) with an AGit push. The Actions token can't: Forgejo 15's AGit
  # looks the pusher up with GetUserByID (services/agit/agit.go), which has
  # no row for the Actions user (-2). ci-bot reads omnissiah and writes
  # nothing there, so the HOM-32 trust check still sees manjo as its only
  # writer. Its PAT is minted here, logged in as ci-bot with the generated
  # password, and goes straight into the CI_PUSH_TOKEN secret.
  #
  # First apply: the provider logs in when it is configured, so create the
  # account alone first (README, "Machines pull requests"):
  #   nix run .#tofunix -- apply -target=gitea_user.ci-bot
  ciBot = "ci-bot";
  ciCredential = "tofunix-ci-bot-forgejo-password";
  manageCiBot = builtins.pathExists (vars.shared ciCredential ciCredential);
in {
  reliquary.ntfy_access = {
    generator = "ntfy-access";
    file = "alertmanager-ntfy";
  };

  # Unrelated plans must still work before the bot password is generated.
  reliquary.hermes_password = lib.mkIf manageBot {
    generator = passwordCredential;
  };

  resource.gitea_user =
    lib.optionalAttrs manageBot {
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
    }
    // lib.optionalAttrs manageCiBot {
      ${ciBot} = {
        provider = "gitea.cerberus";
        username = ciBot;
        login_name = ciBot;
        email = "ci-bot@forge.ugalabugala.org";
        password = relic "ci_bot_password" "password";
        # Restricted: it sees only the repositories it is a collaborator of.
        restricted = true;
        admin = false;
        active = true;
        max_repo_creation = 0;
        allow_create_organization = false;
        allow_git_hook = false;
        allow_import_local = false;
        send_notification = false;
        must_change_password = false;
        lifecycle.ignore_changes = ["password"];
      };
    };

  reliquary.ci_bot_password = lib.mkIf manageCiBot {
    generator = ciCredential;
  };
  # Logs in as ci-bot (basic auth) only to mint its token. Configuring it
  # fails until the account exists, hence the targeted first apply.
  provider.gitea.ci_bot = lib.mkIf manageCiBot {
    inherit (config.provider.gitea.cerberus) base_url;
    username = ciBot;
    password = relic "ci_bot_password" "password";
  };
  # write:repository is what a push needs, AGit included (Forgejo checks
  # it in githttp for receive-pack); nothing else. The account's read grant
  # bounds it to opening pull requests on omnissiah.
  resource.gitea_token = lib.optionalAttrs manageCiBot {
    ci-bot-omnissiah = {
      provider = "gitea.ci_bot";
      depends_on = ["gitea_repository_collaborator.omnissiah-ci-bot"];
      name = "omnissiah-machines-ci";
      scopes = ["write:repository"];
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

  # ci-bot's token for the Machines workflow's AGit pull requests. Read only
  # from tofunix state: rotating it is `-replace=gitea_token.ci-bot-omnissiah`.
  resource.forgejo_repository_actions_secret.omnissiah-ci-push-token = lib.mkIf manageCiBot {
    provider = "forgejo.cerberus";
    inherit (config.scriptorium) owner;
    repository = "omnissiah";
    name = "CI_PUSH_TOKEN";
    data = "\${gitea_token.ci-bot-omnissiah.token}";
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
    }
    // lib.optionalAttrs manageCiBot {
      # Read is all AGit needs; anything more would make ci-bot a writer and
      # every omnissiah run untrusted.
      omnissiah-ci-bot = {
        provider = "gitea.cerberus";
        depends_on = [
          "gitea_user.${ciBot}"
          "gitea_repository_branch_protection.omnissiah"
        ];
        inherit owner;
        repo = "omnissiah";
        username = ciBot;
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
    (lib.filterAttrs (_: repo: repo.protect or true) repos)
    # Enrolling omnissiah in `repos` would make this rule silently replace
    # the generic one: move it there instead.
    // lib.throwIf (repos ? omnissiah) "forge-cerberus.nix: omnissiah has a standalone branch rule; move it into `repos` before enrolling it there" {
      # omnissiah, not in `repos`: no Hermes grant or fork. The HOM-32
      # dispatcher trusts its runs (uploads to ncps, the Machines closure
      # check) only while master has exactly this kind of rule: pushes and
      # merges by manjo alone. manjo keeps pushing master directly, vars
      # commits included; the Machines workflow's flake.lock goes through a
      # pull request opened by ci-bot (.forgejo/workflows/machines.yml).
      # Forgejo also refuses every force push to a protected branch, manjo's
      # included. No status checks: no workflow runs on pull_request.
      omnissiah = {
        provider = "gitea.cerberus";
        name = "omnissiah";
        username = owner;
        rule_name = "master";
        enable_push = true;
        push_whitelist_users = [owner];
        merge_whitelist_users = [owner];
        required_approvals = 0;
        status_check_patterns = [];
      };
    };
}
