# auspex: a TUI that scans the Clan fleet (reachability, drift, deploys). A rust-app-template
# product (`cli new auspex`), developed on forge.noosphere.uk and pushed with AGit only, and
# push-mirrored to GitHub (the GitHub repo itself is created by hand; tofunix does not manage it).
{ref, ...}: {
  resource.forgejo_repository.auspex = {
    name = "auspex";
    description = "Fleet scanner TUI for Clan: reachability, drift, previews and deploys";
    private = false;
    default_branch = "master";
    has_pull_requests = true;
    has_actions = true;
    has_issues = true;
  };

  resource.forgejo_repository_push_mirror.auspex-github = {
    owner = "manjo";
    # A reference, not the literal name, so the mirror is created after the repo.
    repository = ref.forgejo_repository.auspex.name;
    remote_address = "https://github.com/apetrovic6/auspex";
    sync_on_commit = true;
    use_ssh = true;
  };
}
