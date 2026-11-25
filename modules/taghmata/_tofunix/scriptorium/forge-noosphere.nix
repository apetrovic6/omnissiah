# forge.noosphere.uk, the cluster forge: its organisation, its repositories and
# where each is mirrored (./../patterns/repos.nix).
{
  config,
  lib,
  noosphere,
  ref,
  relic,
  vars,
  ...
}: let
  inherit (config.scriptorium) owner;
  bot = "hermes";
  passwordCredential = "tofunix-hermes-noosphere-password";
  manageBot = builtins.pathExists (vars.shared passwordCredential passwordCredential);
  # Explicit upstream read grants, one repo name each. Once the fork token
  # exists, each also gets its hermes/<repo> fork.
  hermesRepos = [
    "auspex"
    "inanna"
    "tally"
  ];
  forkCredential = "tofunix-hermes-noosphere-forks";
  manageForks = manageBot && builtins.pathExists (vars.shared forkCredential forkCredential);
  # The upstream owner: the repo's org (scriptorium.repos.<repo>.org) or manjo.
  upstreamOwner = repo: let
    org = (config.scriptorium.repos.${repo} or {}).org or null;
  in
    if org != null
    then org
    else owner;
in {
  reliquary.hermes_noosphere_password = lib.mkIf manageBot {
    generator = passwordCredential;
  };

  resource.gitea_user = lib.optionalAttrs manageBot {
    hermes_noosphere = {
      provider = "gitea.noosphere";
      username = bot;
      login_name = bot;
      email = "hermes@forge.${noosphere.domain}";
      password = relic "hermes_noosphere_password" "password";
      restricted = true;
      admin = false;
      active = true;
      max_repo_creation = builtins.length hermesRepos;
      allow_create_organization = false;
      allow_git_hook = false;
      allow_import_local = false;
      send_notification = false;
      must_change_password = false;
      lifecycle.ignore_changes = ["password"];
    };
  };

  resource.gitea_repository_collaborator = lib.optionalAttrs manageBot (builtins.listToAttrs (map (repo:
    lib.nameValuePair "${repo}-hermes-noosphere" {
      provider = "gitea.noosphere";
      owner = upstreamOwner repo;
      inherit repo;
      # A repo declared here must exist before it can be granted.
      depends_on = lib.optional (config.scriptorium.repos ? ${repo}) "forgejo_repository.${repo}";
      inherit (ref.gitea_user.hermes_noosphere) username;
      permission = "read";
    })
  hermesRepos));

  # Forks are created as hermes, with an operator-only hermes PAT that never
  # reaches Stygies. Omit the alias and the forks together until it exists.
  reliquary.hermes_noosphere_fork_secrets = lib.mkIf manageForks {
    generator = forkCredential;
  };
  provider.gitea.hermes-noosphere = lib.mkIf manageForks {
    inherit (config.provider.gitea.noosphere) base_url;
    token = relic "hermes_noosphere_fork_secrets" "forgejo_token";
  };
  resource.gitea_fork = lib.optionalAttrs manageForks (builtins.listToAttrs (map (repo:
    lib.nameValuePair "${repo}-noosphere" {
      provider = "gitea.hermes-noosphere";
      depends_on = ["gitea_repository_collaborator.${repo}-hermes-noosphere"];
      owner = upstreamOwner repo;
      inherit repo;
      lifecycle.prevent_destroy = true;
    })
  hermesRepos));

  resource.forgejo_organization.monolith-softworks = {
    name = "monolith-softworks";
    full_name = "Monolith Softworks";
  };

  scriptorium.repos = {
    inanna = {
      org = ref.forgejo_organization.monolith-softworks.name;
      description = "portfolio tracker";
    };

    tally = {
      org = ref.forgejo_organization.monolith-softworks.name;
      description = "tally";
    };

    nvf.description = "Neovim NVF";
    chirp-backend.description = "Chirp backend";
    chirp-client = {
      description = "Chirp client";
      defaultBranch = "main";
    };

    sabnzbd-tui = {
      description = "TUI for SABnzbd";
      mirrors.github.remote_address = "https://github.com/apetrovic6/sabnzbd-tui";
      mirrors.codeberg.remote_address = "https://codeberg.org/apetrovic/sabnzbd-tui";
    };

    # A TUI that scans the Clan fleet (reachability, drift, deploys). A
    # rust-app-template product (`cli new auspex`), developed here, pushed with
    # AGit only, and mirrored to github.com/apetrovic6/auspex.
    auspex = {
      description = "Fleet scanner TUI for Clan: reachability, drift, previews and deploys";
      mirrors.github = {
        # References, not literal names, so the mirror is created after both repositories.
        repository = ref.forgejo_repository.auspex.name;
        remote_address = ref.github_repository.auspex.http_clone_url;
        # HTTPS with the token instead of SSH: an SSH mirror needs its generated key added on
        # GitHub by hand, and the forgejo provider does not expose that key.
        use_ssh = false;
        remote_username = "apetrovic6";
        remote_password = relic "github_secrets" "github_token";
      };
    };
  };

  # The GitHub side of the auspex mirror, created here so nothing is set up by
  # hand on either forge.
  resource.github_repository.auspex = {
    name = "auspex";
    description = "Mirror of forge.noosphere.uk/manjo/auspex. Fleet scanner TUI for Clan.";
    visibility = "public";
    # The forge is the source of truth: issues and PRs live there, not on the mirror.
    has_issues = false;
    has_projects = false;
    has_wiki = false;
    # An empty repository, so the first mirror push isn't rejected by an initial commit.
    auto_init = false;
  };
}
