# auspex: a TUI that scans the Clan fleet (reachability, drift, deploys). A rust-app-template
# product (`cli new auspex`), developed on forge.noosphere.uk and pushed with AGit only, and
# push-mirrored to github.com/apetrovic6/auspex.
#
# Both repositories are created here: the GitHub one by the github provider (_tofunix/github),
# and the mirror over HTTPS with the same token, so nothing is set up by hand on either forge.
# Until the `tofunix-github-secret` var exists, only the Forgejo repository is planned.
{ref, ...}: let
  inherit (import ../../../../../cartographa/_cartographa.nix) vars;
  hasGithubToken =
    builtins.pathExists (vars.shared "tofunix-github-secret" "tofunix-github-secret");
in {
  # One `resource` set, merged one level down: a top-level `//` would replace it wholesale.
  resource =
    {
      forgejo_repository.auspex = {
        name = "auspex";
        description = "Fleet scanner TUI for Clan: reachability, drift, previews and deploys";
        private = false;
        default_branch = "master";
        has_pull_requests = true;
        has_actions = true;
        has_issues = true;
      };
    }
    // (
      if !hasGithubToken
      then {}
      else {
        github_repository.auspex = {
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

        forgejo_repository_push_mirror.auspex-github = {
          owner = "manjo";
          # References, not literal names, so the mirror is created after both repositories.
          repository = ref.forgejo_repository.auspex.name;
          remote_address = ref.github_repository.auspex.http_clone_url;
          # HTTPS with the token instead of SSH: an SSH mirror needs its generated key added on
          # GitHub by hand, and the forgejo provider does not expose that key.
          use_ssh = false;
          remote_username = "apetrovic6";
          remote_password = "\${data.sops_file.github_secrets.data[\"github_token\"]}";
          sync_on_commit = true;
        };
      }
    );
}
