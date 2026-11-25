# Hermes work coder on stygies (HOM-36): the `work` profile's terminal pushes
# task branches to company repos as manjo's own accounts and opens PRs (GitHub)
# or MRs (GitLab) through wrapped CLIs. Companies, rooms and repos live in
# machines/ryza/_work-projects.nix; nothing exists here for a disabled one.
#
# Guard rails, not a sandbox (README, "Hermes work coder"): the agent runs as
# `hermes`, which can read the token files. Company branch protection is the
# backstop.
{...}: {
  flake.nixosModules.hermes-work-coder = {
    config,
    lib,
    pkgs,
    ...
  }: let
    registry = import ../../machines/ryza/_work-projects.nix;
    # The personal coder's forges: the push guard passes their URLs and fails
    # closed for any other HTTP(S) host.
    personalHosts = lib.unique (lib.mapAttrsToList (_: forge: forge.host) (import ../../machines/ryza/_coder-projects.nix).forges);
    companies = lib.filterAttrs (_: company: company.enabled) (registry.check config.services.imperium.hermesWork.companies);
    anyEnabled = companies != {};
    home = config.users.users.hermes.home;
    vars = config.clan.core.vars.generators;
    tokenPath = company: vars.${company.tokenGenerator}.files.token.path;
    identityPath = company: vars.${company.identityGenerator}.files.gitconfig.path;
    stateDir = name: "${home}/work/.tasks/${name}";
    cliPackage = company:
      if company.kind == "github"
      then pkgs.gh
      else pkgs.glab;
    cliName = company:
      if company.kind == "github"
      then "gh"
      else "glab";

    toolsConfig = pkgs.writeText "hermes-work-tools.json" (builtins.toJSON {
      inherit (registry) branchPattern;
      inherit personalHosts;
      # Body files may not come from here (or link here): a slip would post a
      # token. The token and identity files themselves are refused too.
      secretPaths = [
        "/run/secrets"
        "/run/secrets-for-users"
        "/run/credentials"
        "${home}/.ssh"
        "${home}/.local/share/forgejo-cli"
        "${home}/.config/hermes-work"
      ];
      companies =
        lib.mapAttrs (name: company: {
          inherit (company) kind host gitUsername;
          tokenFile = tokenPath company;
          identityFile = identityPath company;
          stateDir = stateDir name;
          configDir = "${home}/.config/hermes-work/${name}/${cliName company}";
          cli = lib.getExe (cliPackage company);
          repos = lib.mapAttrs (_: repo: repo.path) company.repos;
        })
        companies;
    });
    # Hooks run with Git's PATH, so the guard's own `git` calls use the same Git.
    tools = pkgs.writeShellScript "hermes-work-git" ''
      exec ${lib.getExe pkgs.python3} -I ${./_hermes-work-tools.py} ${toolsConfig} "$@"
    '';

    # Not secret: a bare `git push` does nothing in company repos, so every
    # push names its refspec (and meets the guard).
    pushConfig = pkgs.writeText "hermes-work-push.gitconfig" ''
      [push]
        default = nothing
    '';
    # Both URL forms: a credential or includeIf pattern for `o/r` does not
    # match `o/r.git` (Git compares path components).
    repoUrls = company: repo: [
      "https://${company.host}/${repo.path}.git"
      "https://${company.host}/${repo.path}"
    ];
    companyGitConfig = name: company:
      lib.concatMapStrings (url: ''
        [credential "${url}"]
          helper =
          helper = ${tools} credential ${name}
          useHttpPath = true
        [includeIf "hasconfig:remote.*.url:${url}"]
          path = ${pushConfig}
          path = ${identityPath company}
      '') (lib.concatMap (repoUrls company) (lib.attrValues company.repos));
    gitConfig =
      ''
        # Hermes work coder: refuses company pushes outside the active task's
        # branch and identity, and HTTP(S) pushes to unknown hosts; passes
        # the personal forges.
        [hook "hermes-work-guard"]
          event = pre-push
          command = ${tools} pre-push
        [credential]
          interactive = false
        # A redirect would let Git send a company token to a URL the guard
        # never judged. Neither personal forge needs one for Git.
        [http]
          followRedirects = false
      ''
      + lib.concatStrings (lib.mapAttrsToList companyGitConfig companies);

    taskLauncherText = name: company: ''
      umask 077
      export HERMES_TASK_STATE_DIR=${lib.escapeShellArg (stateDir name)}
      export HERMES_TASK_APP_PROJECTS=${lib.escapeShellArg (builtins.toJSON (lib.attrNames company.repos))}
      export HERMES_TASK_PROJECTS="$HERMES_TASK_APP_PROJECTS"
      export HERMES_TASK_ROOMS=${lib.escapeShellArg (builtins.toJSON [company.room])}
      export HERMES_TASK_BRANCH_PATTERN=${lib.escapeShellArg registry.branchPattern}
      # Until stygies's activation has moved ~/work-devzero to ~/work
      # (_hermes-workspace-migrate.py), a fresh slot here would hide its task.
      # Only files count: a stray empty directory is not old state.
      if [ -n "$(${lib.getExe' pkgs.findutils "find"} ${lib.escapeShellArg "${home}/work-devzero"} -mindepth 1 ! -type d -print -quit 2>/dev/null)" ]; then
        printf '%s\n' 'workspace migration pending: ~/work-devzero still holds files.' \
          'If the migration has not run, see README, Hermes workspaces on stygies. If it has (~/work holds the company' \
          'tree), they are strays: check `find ~/work-devzero ! -type d` for anything live, then remove ~/work-devzero.' >&2
        exit 2
      fi
      ${lib.getExe' pkgs.coreutils "mkdir"} -p "$HERMES_TASK_STATE_DIR" || exit $?
      command=''${0##*/}
      ${lib.getExe' pkgs.util-linux "flock"} -w 10 -E 75 "$HERMES_TASK_STATE_DIR/.task-lock" \
        ${lib.getExe pkgs.python3} -I ${./_hermes-task.py} "task-''${command#${name}-task-}" "$@"
      status=$?
      if [ "$status" -eq 75 ]; then
        printf '%s\n' 'task lock busy, retry once' >&2
      fi
      exit "$status"
    '';
    taskLauncher = name: company: pkgs.writeShellScript "hermes-${name}-task" (taskLauncherText name company);
    cliWrapper = name: company:
      pkgs.writeShellScript "${name}-${cliName company}" ''
        exec ${tools} cli ${name} "$@"
      '';
    workTools =
      pkgs.runCommand "hermes-work-tools" {
        # The rendered launchers, for tests/test_hermes_work_launchers.py.
        passthru.launcherTexts = lib.mapAttrs taskLauncherText companies;
      } (''
          mkdir -p "$out/bin"
        ''
        + lib.concatStrings (lib.mapAttrsToList (name: company: ''
            for action in status claim branch done clear drop; do
              ln -s ${taskLauncher name company} "$out/bin/${name}-task-$action"
            done
            ln -s ${cliWrapper name company} "$out/bin/${name}-${cliName company}"
          '')
          companies));

    identityScript = ''
      fail() { printf '%s\n' "$1" >&2; exit 1; }
      for field in name email; do
        value=$(cat "$prompts/$field")
        [ -n "$value" ] || fail "$field is empty"
        [ "$(printf '%s' "$value" | wc -l)" -eq 0 ] || fail "$field must be one line"
        # Values are written quoted: refuse what would end or escape the quotes.
        if printf '%s' "$value" | LC_ALL=C grep -q '[][\"[:cntrl:]]'; then
          fail "$field must not contain [, ], \\, \" or control characters"
        fi
      done
      name=$(cat "$prompts/name")
      email=$(cat "$prompts/email")
      case "$email" in
        *@*@* | @* | *@ | *' '*) fail "email must be one address with exactly one @" ;;
        *@*) ;;
        *) fail "email must be one address with exactly one @" ;;
      esac
      printf '[user]\n  name = "%s"\n  email = "%s"\n' "$name" "$email" > "$out/gitconfig"
    '';
  in {
    # The registry; an option only so checks can evaluate other values.
    options.services.imperium.hermesWork.companies = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = registry.companies;
      description = "Work coder companies (machines/ryza/_work-projects.nix).";
    };

    config.services.imperium.hermesGit.extraConfig = lib.mkIf anyEnabled gitConfig;

    config.clan.core.vars.generators = lib.mkMerge (lib.mapAttrsToList (name: company: let
        label =
          if company.kind == "github"
          then "GitHub fine-grained PAT (resource owner: the ${company.title} org; only the repos in _work-projects.nix; Contents: read and write, Pull requests: read and write)"
          else "${company.host} token (fine-grained, limited to the repos in _work-projects.nix, if the instance offers it; else a PAT with api, read_repository, write_repository)";
        hermesFile = {
          secret = true;
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };
      in {
        ${company.tokenGenerator} = {
          prompts.token = {
            description = "Your own ${label} for Hermes work. Paste only the token.";
            type = "hidden";
          };
          files.token = hermesFile;
          runtimeInputs = [pkgs.coreutils];
          script = ''cp "$prompts/token" "$out/token"'';
        };
        ${company.identityGenerator} = {
          prompts.name = {
            description = "Your git user.name for ${company.title} commits";
            type = "hidden";
          };
          prompts.email = {
            description = "Your git user.email for ${company.title} commits";
            type = "hidden";
          };
          files.gitconfig = hermesFile;
          runtimeInputs = [pkgs.coreutils pkgs.gnugrep];
          script = identityScript;
        };
      })
      companies);

    config.users.users.hermes.packages = lib.optional anyEnabled workTools;

    config.systemd.tmpfiles.settings.hermes-work-coder = lib.mkIf anyEnabled ({
        "${home}/work/.tasks".d = {
          user = "hermes";
          group = "hermes";
          mode = "0700";
        };
        "${home}/.config/hermes-work".d = {
          user = "hermes";
          group = "hermes";
          mode = "0700";
        };
      }
      // lib.mapAttrs' (name: _:
        lib.nameValuePair "${home}/work/${name}" {
          d = {
            user = "hermes";
            group = "hermes";
            mode = "0750";
          };
        })
      companies);
  };
}
