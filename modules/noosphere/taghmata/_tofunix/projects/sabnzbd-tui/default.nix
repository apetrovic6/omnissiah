{ref, ...}: {
  resource.forgejo_repository.sabnzbd-tui = {
    name = "sabnzbd-tui";
    description = "TUI for SABnzbd";
    private = false;
    default_branch = "master";
    has_pull_requests = true;
    has_actions = true;
    has_issues = true;
  };

  resource.forgejo_repository_push_mirror.sabnzbd-tui-github = {
        owner = "manjo";
    repository = "sabnzbd-tui";
    remote_address = "https://github.com/apetrovic6/sabnzbd-tui";
    sync_on_commit = true;
    use_ssh = true;
  };

  resource.forgejo_repository_push_mirror.sabnzbd-tui-codeberg = {
    owner = "manjo";
    repository = "zellij";
    remote_address = "https://codeberg.org/apetrovic/zellij";
    sync_on_commit = true;
    use_ssh = true;
  };
}
