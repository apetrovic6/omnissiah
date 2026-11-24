"""Hermes work coder tools on stygies: Git credential helper, push guard, gh/glab wrapper.

Usage: _hermes-work-tools.py CONFIG.json (credential COMPANY OP | pre-push REMOTE URL | cli COMPANY ARGS...)

CONFIG holds hosts, repo paths and token *paths*, never a token. These are
guard rails against mistakes, not a sandbox: the agent runs as the same user
that can read the token files (README, "Hermes work coder").
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit


ZERO = re.compile(r"0+")
SHA = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")
GUARD = "refused by Hermes push guard"


def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)


def load_config(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def read_token(company):
    try:
        with open(company["tokenFile"], encoding="utf-8") as stream:
            # A Clan prompt file can end at EOF without a newline.
            token = stream.readline().rstrip("\r\n")
    except OSError:
        return None
    return token or None


def strip_git(path):
    return path.removesuffix(".git")


def repo_key(company, path):
    """The registry key for an exact repo path (with or without .git), else None."""
    path = strip_git(path)
    return next((key for key, repo in company["repos"].items() if repo == path), None)


def active_task(company):
    """The active task of this company's slot as a dict, None when idle; raises ValueError."""
    path = Path(company["stateDir"]) / ".current-task"
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    if not text:
        return None
    lines = text.removesuffix("\n").split("\n")
    fields = lines[0].split("\t")
    if len(lines) != 1 or len(fields) != 6:
        raise ValueError("invalid task state")
    return dict(zip(("started_at", "room", "thread", "project", "branch", "summary"), fields))


# --- credential helper ------------------------------------------------------


def credential(config, company_name, operation):
    # Only answer lookups; store/erase are no-ops for a file-backed token.
    if operation != "get":
        return 0
    company = config["companies"].get(company_name)
    if company is None:
        return 0
    fields = {}
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            break
        # Anything but key=value, or a repeated key we match on, is not from Git.
        if "=" not in line:
            return 0
        key, value = line.split("=", 1)
        if key in ("protocol", "host", "username", "path"):
            if key in fields:
                return 0
            fields[key] = value
    if fields.get("protocol") != "https" or fields.get("host") != company["host"]:
        return 0
    # useHttpPath is set for the company's repos: no path, no token.
    if repo_key(company, fields.get("path", "")) is None:
        return 0
    if fields.get("username", "") not in ("", company["gitUsername"]):
        return 0
    token = read_token(company)
    if token is None:
        return 0
    sys.stdout.write(f"username={company['gitUsername']}\npassword={token}\n\n")
    return 0


# --- pre-push guard ---------------------------------------------------------


def url_host(url):
    """Host of a Git URL (https, ssh, scp-like), or None for local paths."""
    if "://" in url:
        try:
            return (urlsplit(url).hostname or "").lower() or None
        except ValueError:
            return None
    match = re.fullmatch(r"(?:[^@/]+@)?([^:/]+):(?!//).*", url)
    return match.group(1).lower() if match else None


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False)


def identity_email(company):
    """The email in the company's Git identity file, or None if missing or empty."""
    result = git("config", "--file", company["identityFile"], "--get", "user.email")
    email = result.stdout.strip() if result.returncode == 0 else ""
    return email or None


def pushed_emails(remote, local_sha, remote_sha):
    """Author and committer emails of the commits this ref update sends."""
    if ZERO.fullmatch(remote_sha):
        revs = [local_sha, "--not", f"--remotes={remote}"]
    else:
        revs = [f"{remote_sha}..{local_sha}"]
    result = git("log", "--format=%ae%n%ce", *revs, "--")
    if result.returncode != 0:
        fail(f"{GUARD}: cannot list the pushed commits")
    return {line for line in result.stdout.splitlines() if line}


def pre_push(config, remote, url):
    host = url_host(url)
    companies = {company["host"]: (name, company) for name, company in config["companies"].items()}
    if host not in companies:
        # An HTTP(S) URL Hermes has no business with could redirect to a
        # company repo and pick up its token; personal forges pass.
        scheme = url.split("://", 1)[0].lower() if "://" in url else ""
        if scheme in ("http", "https") and host not in config["personalHosts"]:
            fail(f"{GUARD}: {host} is neither a company nor a personal forge")
        sys.stdin.read()
        return 0
    name, company = companies[host]
    # Only the exact URL forms the Git config's includeIf covers, so the
    # identity and push.default always apply.
    key = next((key for key, path in company["repos"].items()
                if url in (f"https://{host}/{path}.git", f"https://{host}/{path}")), None)
    if key is None:
        fail(f"{GUARD}: {name} pushes must use a listed repo as https://{host}/<path>.git")
    try:
        task = active_task(company)
    except ValueError:
        fail(f"{GUARD}: {name} task state is invalid; ask manjo for 'clear task'")
    if task is None or task["branch"] == "pending":
        fail(f"{GUARD}: no active {name} task with a recorded branch ({name}-task-branch)")
    if task["project"] != key:
        fail(f"{GUARD}: the active {name} task is for {task['project']}, not {key}")
    branch = task["branch"]
    if not re.fullmatch(config["branchPattern"], branch):
        fail(f"{GUARD}: recorded branch {branch!r} does not match the branch naming rule")
    head = git("symbolic-ref", "-q", f"refs/remotes/{remote}/HEAD")
    prefix = f"refs/remotes/{remote}/"
    if head.returncode != 0 or not head.stdout.strip().startswith(prefix):
        fail(f"{GUARD}: unknown default branch; push through a named remote after `git remote set-head {remote} --auto`")
    default = head.stdout.strip().removeprefix(prefix)
    if branch == default:
        fail(f"{GUARD}: {branch} is the default branch")
    email = identity_email(company)
    if email is None:
        fail(f"{GUARD}: the {name} Git identity file is missing or empty; ask manjo to provision it")

    for line in sys.stdin:
        fields = line.split()
        if not fields:
            continue
        if len(fields) != 4:
            fail(f"{GUARD}: unexpected pre-push input")
        _local_ref, local_sha, remote_ref, remote_sha = fields
        if remote_ref != f"refs/heads/{branch}":
            fail(f"{GUARD}: only refs/heads/{branch} (the task's branch) may be pushed, not {remote_ref}")
        if not SHA.fullmatch(local_sha) or not SHA.fullmatch(remote_sha):
            fail(f"{GUARD}: unexpected object names")
        if ZERO.fullmatch(local_sha):
            fail(f"{GUARD}: deleting {remote_ref} is not allowed")
        if not ZERO.fullmatch(remote_sha):
            if git("cat-file", "-e", f"{remote_sha}^{{commit}}").returncode != 0:
                fail(f"{GUARD}: {remote_ref} moved on the remote; fetch first")
            if git("merge-base", "--is-ancestor", remote_sha, local_sha).returncode != 0:
                fail(f"{GUARD}: non-fast-forward push to {remote_ref}; add commits instead of rewriting")
        others = {other for other in pushed_emails(remote, local_sha, remote_sha) if other.lower() != email.lower()}
        if others:
            fail(f"{GUARD}: pushed commits must be authored and committed with the {name} identity "
                 f"({len(others)} other address(es)); fix the commits before pushing")
    return 0


# --- gh / glab wrapper ------------------------------------------------------
#
# Allowlists, not denylists: every subcommand lists its flags and whether each
# takes a value, parsed the way pflag does (a value-taking option consumes the
# next element whatever it is). Anything unlisted is refused. Re-check the
# arity with tests/test_hermes_work_cli_arity.py whenever gh or glab changes.


def flags(text):
    """'-R --repo=, --draft' -> ({'--repo': True, '--draft': False}, {'-R': '--repo'})."""
    longs, shorts = {}, {}
    for item in filter(None, (part.strip() for part in text.split(","))):
        *aliases, name = item.split()
        longs[name.rstrip("=")] = name.endswith("=")
        for alias in aliases:
            shorts[alias] = name.rstrip("=")
    return longs, shorts


class Command:
    def __init__(self, spec, positionals=(0, 0), repo="flag", bind=None):
        self.longs, self.shorts = flags(spec)
        self.positionals = positionals
        self.repo = repo  # "flag": --repo required; "positional": first argument; "api": the endpoint
        self.bind = bind  # write: "--head"/"--source-branch" flag, or "selector" positional, equals the task branch


REPO = "-R --repo=, "
JSON = "--json=, -q --jq=, "
GH = {
    ("pr", "create"): Command(REPO + "-B --base=, -H --head=, -t --title=, -b --body=, -F --body-file=, -d --draft",
                              bind="--head"),
    ("pr", "view"): Command(REPO + JSON + "-c --comments", (0, 1)),
    ("pr", "list"): Command(REPO + JSON + "-B --base=, -H --head=, -A --author=, -s --state=, -L --limit="),
    ("pr", "diff"): Command(REPO + "--name-only, --patch, --color=", (0, 1)),
    ("pr", "checks"): Command(REPO + JSON + "--required", (0, 1)),
    ("pr", "status"): Command(REPO + JSON),
    ("pr", "comment"): Command(REPO + "-b --body=, -F --body-file=", (1, 1), bind="selector"),
    ("pr", "edit"): Command(REPO + "-t --title=, -b --body=, -F --body-file=", (1, 1), bind="selector"),
    ("pr", "ready"): Command(REPO, (1, 1), bind="selector"),
    ("repo", "view"): Command(JSON, (1, 1), repo="positional"),
    ("run", "list"): Command(REPO + JSON + "-b --branch=, -c --commit=, -L --limit=, -s --status=, -w --workflow="),
    ("run", "view"): Command(REPO + JSON + "-a --attempt=, --exit-status, -j --job=, --log, --log-failed, -v --verbose",
                             (0, 1)),
    ("run", "watch"): Command(REPO + "--compact, --exit-status, -i --interval=", (1, 1)),
    ("api",): Command("-X --method=, --paginate, -q --jq=, -i --include, --silent, -H --header=", (1, 1), repo="api"),
}
GL_OUT = "-F --output=, --jq=, "
GLAB = {
    ("mr", "create"): Command(REPO + "-s --source-branch=, -b --target-branch=, -t --title=, -d --description=, "
                              "--description-file=, --draft, --push, -y --yes", bind="--source-branch"),
    ("mr", "view"): Command(REPO + GL_OUT + "-c --comments", (0, 1)),
    ("mr", "list"): Command(REPO + GL_OUT + "-s --source-branch=, -t --target-branch=, -A --all, -c --closed, "
                            "-M --merged, -P --per-page="),
    ("mr", "diff"): Command(REPO + "--raw, --color=", (0, 1)),
    ("mr", "note", "create"): Command(REPO + "-m --message=", (1, 1), bind="selector"),
    ("mr", "update"): Command(REPO + "-t --title=, -d --description=, --description-file=, --draft, -r --ready, -y --yes",
                              (1, 1), bind="selector"),
    ("repo", "view"): Command(GL_OUT, (1, 1), repo="positional"),
    ("ci", "list"): Command(REPO + GL_OUT + "-r --ref=, -s --status=, -P --per-page="),
    ("ci", "get"): Command(REPO + GL_OUT + "-b --branch=, -p --pipeline-id=, -d --with-job-details"),
    ("ci", "status"): Command(REPO + "-b --branch=, -c --compact"),
    ("ci", "trace"): Command(REPO + "-b --branch=, -p --pipeline-id=", (0, 1)),
    ("api",): Command("-X --method=, --paginate, -i --include, --silent, --output=", (1, 1), repo="api"),
}
SPECS = {"github": GH, "gitlab": GLAB}
SCRUB = ("GH_", "GITHUB_", "GITLAB_", "GLAB_", "GL_")
# jq can read the environment, which holds the token.
JQ_ENV = re.compile(r"\benv\b|\$ENV|\$__loc__")


def refuse(message):
    fail(f"refused by Hermes work wrapper: {message}", 2)


def parse(command, args):
    """pflag-style parse against the allowlist: (flags by long name, positionals)."""
    found, positionals = {}, []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            refuse("a bare `--` is not allowed")
        if arg.startswith("--"):
            name, eq, value = arg.partition("=")
            if name not in command.longs:
                refuse(f"{name} is not an allowed flag here")
            takes = command.longs[name]
            if takes and not eq:
                i += 1
                if i >= len(args):
                    refuse(f"{name} needs a value")
                value = args[i]
            elif not takes:
                if eq and value not in ("true", "false"):
                    refuse(f"{name} takes true or false")
                value = value == "true" if eq else True
        elif arg.startswith("-") and arg != "-":
            # Single-dash: only a listed short flag on its own (no bundles, no attached value).
            if arg not in command.shorts:
                refuse(f"{arg} is not an allowed flag here (use listed long options)")
            name = command.shorts[arg]
            value = True
            if command.longs[name]:
                i += 1
                if i >= len(args):
                    refuse(f"{arg} needs a value")
                value = args[i]
        else:
            positionals.append(arg)
            i += 1
            continue
        if value == "--":
            refuse("a bare `--` is not allowed")
        if name in found:
            refuse(f"{name} given more than once")
        found[name] = value
        i += 1
    low, high = command.positionals
    if not low <= len(positionals) <= high:
        refuse(f"expected {low}-{high} positional argument(s), got {len(positionals)}")
    return found, positionals


def check_endpoint(kind, company, endpoint):
    if endpoint == "user":  # the auth check
        return
    decoded = unquote(endpoint)
    if ("://" in endpoint or endpoint.startswith("/") or ".." in decoded or "//" in decoded or "graphql" in decoded.lower()
            or any(char in decoded for char in ":{}\\") or any(char.isspace() for char in decoded)):
        refuse("api endpoints must be relative REST paths under a listed repo")
    if kind == "github":
        prefixes = [f"repos/{path}" for path in company["repos"].values()]
    else:
        prefixes = [f"projects/{quote(path, safe='')}" for path in company["repos"].values()]
    if not any(endpoint == prefix or endpoint.startswith((prefix + "/", prefix + "?")) for prefix in prefixes):
        refuse("api endpoints must be under a listed repo (repos/<owner>/<name> or projects/<url-encoded path>)")


def task_for(company, repo):
    try:
        task = active_task(company)
    except ValueError:
        refuse("task state is invalid; ask manjo for 'clear task'")
    if task is None or task["branch"] == "pending":
        refuse("writes need an active task with a recorded branch")
    if repo_key(company, repo) != task["project"]:
        refuse(f"the active task is for {task['project']}")
    return task


def check_cli(kind, company, args):
    specs = SPECS[kind]
    words = next((key for key in specs if tuple(args[: len(key)]) == key), None)
    if words is None:
        allowed = ", ".join(" ".join(key) for key in specs)
        refuse(f"allowed commands: {allowed}")
    command = specs[words]
    found, positionals = parse(command, args[len(words):])
    for name in ("--jq",):
        if name in found and JQ_ENV.search(found[name]):
            refuse("--jq must not read the environment")
    if command.repo == "api":
        method = found.get("--method", "GET")
        if method.upper() != "GET":
            refuse("api is read-only (GET)")
        header = found.get("--header")
        if header is not None and not header.lower().startswith("accept:"):
            refuse("api allows only an Accept header")
        check_endpoint(kind, company, positionals[0])
        return
    if command.repo == "positional":
        if repo_key(company, positionals[0]) is None:
            refuse(f"{' '.join(words)} needs an enabled repo path")
        return
    repo = found.get("--repo")
    if repo is None or repo_key(company, repo) is None:
        refuse("--repo must name an enabled repo path")
    if found.get("--push", False) is not False:
        refuse("mr create must not push; push with git, then pass --push=false")
    if command.bind is None:
        return
    task = task_for(company, repo)
    value = positionals[0] if command.bind == "selector" else found.get(command.bind)
    if value != task["branch"]:
        what = "the PR/MR selector" if command.bind == "selector" else command.bind
        refuse(f"{what} must be {task['branch']} (the task's branch)")


def cli(config, company_name, args):
    company = config["companies"].get(company_name)
    if company is None:
        refuse(f"{company_name} is not enabled")
    kind = company["kind"]
    check_cli(kind, company, args)
    token = read_token(company)
    if token is None:
        fail(f"{company_name}: token file missing or empty; see the README", 1)
    env = {key: value for key, value in os.environ.items() if not key.startswith(SCRUB)}
    env["DO_NOT_TRACK"] = "1"
    if kind == "github":
        env.update(
            GH_TOKEN=token,
            GH_HOST=company["host"],
            GH_CONFIG_DIR=company["configDir"],
            GH_PROMPT_DISABLED="1",
            GH_NO_UPDATE_NOTIFIER="1",
            GH_NO_EXTENSION_UPDATE_NOTIFIER="1",
            GH_TELEMETRY="0",
            GH_SPINNER_DISABLED="1",
        )
    else:
        # Not XDG_CONFIG_HOME: Git run by glab would miss Hermes's Git config.
        env.update(
            GITLAB_TOKEN=token,
            GITLAB_HOST=company["host"],
            GLAB_SEND_TELEMETRY="0",
            GLAB_CHECK_UPDATE="false",
            GLAB_NO_PROMPT="1",
        )
    binary = company["cli"]
    os.execve(binary, [os.path.basename(binary), *args], env)


def main():
    if len(sys.argv) < 3:
        fail(__doc__.strip().splitlines()[2], 2)
    config = load_config(sys.argv[1])
    command, rest = sys.argv[2], sys.argv[3:]
    if command == "credential" and len(rest) == 2:
        return credential(config, *rest)
    if command == "pre-push" and len(rest) == 2:
        return pre_push(config, *rest)
    if command == "cli" and rest:
        return cli(config, rest[0], rest[1:])
    fail(__doc__.strip().splitlines()[2], 2)


if __name__ == "__main__":
    sys.exit(main())
