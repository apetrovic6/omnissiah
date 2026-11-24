# Hermes work coder (HOM-36): company forges, their Matrix rooms and repo
# allowlists. Read by machines/ryza/hermes.nix (work SOUL and room routes) and
# modules/rites/hermes-work-coder.nix (stygies credentials, guard, task slots).
#
# A company stays `enabled = false` until its token and Git identity vars
# exist (README, "Hermes work coder"). While off, neither var is declared, so
# no deploy prompts for them, and stygies gets no credentials, CLI or task slot
# for it. Enable it in the same commit as its generated vars.
#
# Add a repo: `repos.<key> = { path = "<owner>/<name>"; };` (GitHub) or
# `path = "<group>/<subgroup>/<project>";` (GitLab). The key is the task
# project name (letters, digits, `.`, `_`, `-`), unique within the company.
# For GitHub, also add the repo to the fine-grained PAT's selected repos.
let
  companies = {
    devzero = {
      title = "DevZero";
      enabled = false;
      kind = "github";
      host = "github.com";
      room = "!9W1zTDhbkbNc7vh-H_aFbS66CxFZ29FL1z-tmoQUUYc";
      tokenGenerator = "hermes-work-devzero-github-token";
      # Commit name and email: a secret var (hidden prompts), never in Nix.
      identityGenerator = "hermes-work-devzero-git-identity";
      # Required for Git over HTTPS but not used to authenticate (GitHub PAT docs).
      gitUsername = "x-access-token";
      # Jira project keys (e.g. "DEV") whose tickets belong to this company.
      jiraProjects = [];
      repos = {
        # api = { path = "devzero-inc/api"; };
      };
    };
    codilas = {
      title = "Codilas";
      enabled = false;
      kind = "gitlab";
      host = "gitlab.codilas.com";
      room = "!j3n_ajvQEN1cZ_dH3uKMgLld6k_haMuTJ4Kj8dnW5k4";
      tokenGenerator = "hermes-work-codilas-gitlab-token";
      identityGenerator = "hermes-work-codilas-git-identity";
      # GitLab accepts any non-empty username with a PAT.
      gitUsername = "hermes";
      jiraProjects = [];
      repos = {
        # backend = { path = "codilas/platform/backend"; };
      };
    };
  };

  # Task branches: <type>/<JIRA-KEY>-<slug>. Checked by <company>-task-branch
  # and again by the push guard.
  branchPattern = "^(feature|fix|chore)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9][a-z0-9-]*$";

  inherit (builtins) all attrNames attrValues concatStringsSep elem filter foldl' length match replaceStrings;
  upper = ["A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z"];
  lower = ["a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z"];
  file = "machines/ryza/_work-projects.nix";
  require = cond: message:
    if cond
    then true
    else throw "${file}: ${message}";
  checkCompany = name: company: let
    keys = attrNames company.repos;
    badKeys = filter (key: match "[A-Za-z0-9][A-Za-z0-9._-]*" key == null) keys;
    badPaths = filter (key: let
      path = company.repos.${key}.path;
    in
      match "[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+" path == null || match ".*\\.git" path != null)
    keys;
    badJira = filter (key: match "[A-Z][A-Z0-9]+" key == null) company.jiraProjects;
    # Two keys for one repo: only the first could ever push or open a PR/MR.
    # GitHub paths are case-insensitive.
    canonical = path:
      if company.kind == "github"
      then replaceStrings upper lower path
      else path;
    paths = map (key: canonical company.repos.${key}.path) keys;
    duplicates = foldl' (seen: path:
      if elem path seen || length (filter (other: other == path) paths) < 2
      then seen
      else seen ++ [path]) []
    paths;
  in
    require (company.enabled || keys == []) "${name} lists repos but has enabled = false. Finish its token and identity steps in the README, then set enabled = true in the same commit as its vars."
    && require (badKeys == []) "${name} repo key(s) ${concatStringsSep ", " badKeys} must be task project names (letters, digits, '.', '_', '-')."
    && require (badPaths == []) "${name} repo(s) ${concatStringsSep ", " badPaths} need a path like owner/name or group/sub/project, without .git."
    && require (duplicates == []) "${name} lists the repo path(s) ${concatStringsSep ", " duplicates} under more than one key."
    && require (badJira == []) "${name} jiraProjects must be Jira project keys like DEV."
    && require (company.kind == "github" || company.kind == "gitlab") "${name}.kind must be github or gitlab.";
  # Throws on the first problem, else returns the companies unchanged.
  check = companies: let
    enabledHosts = map (company: company.host) (filter (company: company.enabled) (attrValues companies));
    uniqueHosts = all (host: length (filter (other: other == host) enabledHosts) == 1) enabledHosts;
  in
    assert all (name: checkCompany name companies.${name}) (attrNames companies);
    assert require uniqueHosts "two enabled companies share a host; the credential helper and push guard map one host to one company."; companies;
in {
  companies = check companies;
  inherit branchPattern check;
}
