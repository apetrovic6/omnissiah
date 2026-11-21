# forge.noosphere.uk, the cluster forge: its organisation, its repositories and
# where each is mirrored (./../patterns/repos.nix).
{
  ref,
  relic,
  ...
}: {
  resource.forgejo_organization.monolith-softworks = {
    name = "monolith-softworks";
    full_name = "Monolith Softworks";
  };

  scriptorium.repos = {
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
