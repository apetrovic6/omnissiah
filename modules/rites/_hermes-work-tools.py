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
from urllib.parse import urlsplit


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


def pre_push(config, remote, url):
    host = url_host(url)
    companies = {company["host"]: (name, company) for name, company in config["companies"].items()}
    if host not in companies:
        # Forgejo and other hosts: the personal coder's pushes are not ours to judge.
        sys.stdin.read()
        return 0
    name, company = companies[host]
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        fail(f"{GUARD}: unparsable URL")
    if parts.scheme != "https" or parts.username or parts.password or port or parts.query or parts.fragment:
        fail(f"{GUARD}: {name} pushes must use https://{host}/<repo>.git without credentials or a port")
    path = parts.path.removeprefix("/").removesuffix("/")
    key = repo_key(company, path)
    if key is None:
        fail(f"{GUARD}: {path} is not an enabled {name} repo")
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
    return 0


# --- gh / glab wrapper ------------------------------------------------------


GH = {
    "pr": {"create", "view", "list", "diff", "checks", "comment", "edit", "status", "ready"},
    "repo": {"view"},
    "run": {"list", "view", "watch"},
    "auth": {"status"},
    "api": None,
}
GLAB = {
    "mr": {"create", "view", "list", "diff", "note", "update"},
    "repo": {"view"},
    "ci": {"list", "get", "status", "trace"},
    "auth": {"status"},
    "api": None,
}
SCRUB = ("GH_", "GITHUB_", "GITLAB_", "GLAB_", "GL_")


def refuse(message):
    fail(f"refused by Hermes work wrapper: {message}", 2)


def options(args, longs, shorts=()):
    """Values of the given options (`--x v`, `--x=v`, `-x v`) up to `--`."""
    values = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            break
        for name in longs:
            if arg == name:
                if i + 1 >= len(args):
                    refuse(f"{name} needs a value")
                values.append(args[i + 1])
                i += 1
            elif arg.startswith(name + "="):
                values.append(arg[len(name) + 1:])
        if arg in shorts:
            if i + 1 >= len(args):
                refuse(f"{arg} needs a value")
            values.append(args[i + 1])
            i += 1
        i += 1
    return values


def has_flag(args, *names):
    return any(arg in names or arg.split("=", 1)[0] in names for arg in args[: args.index("--") if "--" in args else None])


def one(args, longs, shorts, what):
    values = options(args, longs, shorts)
    if len(set(values)) > 1:
        refuse(f"{what} given more than once")
    return values[0] if values else None


def check_api(args):
    if len(args) < 2 or "graphql" in args:
        refuse("api needs a REST endpoint (graphql is not allowed)")
    if has_flag(args, "--hostname"):
        refuse("api --hostname is not allowed")
    methods = options(args, ("--method",), ("-X",))
    if any(method.upper() != "GET" for method in methods):
        refuse("api is read-only (GET)")
    body = has_flag(args, "-f", "-F", "--field", "--raw-field", "--input")
    if body and not methods:
        refuse("api fields need an explicit --method GET")


def check_cli(kind, company, args):
    groups = GH if kind == "github" else GLAB
    if not args or args[0] not in groups:
        refuse(f"allowed commands: {', '.join(sorted(groups))}")
    group = args[0]
    for arg in args[: args.index("--") if "--" in args else None]:
        # `-xV` clusters could hide a value option from the checks below.
        if arg.startswith("-") and not arg.startswith("--") and len(arg) > 2:
            refuse(f"use long options or separate values, not {arg}")
    if group == "api":
        check_api(args)
        return
    if len(args) < 2 or args[1] not in groups[group]:
        refuse(f"allowed {group} subcommands: {', '.join(sorted(groups[group]))}")
    sub = args[1]
    if group == "auth":
        if has_flag(args, "--show-token", "-t"):
            refuse("auth status --show-token is not allowed")
        return
    if has_flag(args, "--hostname"):
        refuse("--hostname is not allowed")
    if group == "repo":
        if len(args) < 3 or repo_key(company, args[2]) is None:
            refuse("repo view needs an enabled repo path right after `view`")
        return
    repo = one(args, ("--repo",), ("-R",), "--repo")
    if repo is None or repo_key(company, repo) is None:
        refuse("--repo must name an enabled repo path")
    if sub != "create":
        return
    try:
        task = active_task(company)
    except ValueError:
        refuse("task state is invalid; ask manjo for 'clear task'")
    if task is None or task["branch"] == "pending":
        refuse("no active task with a recorded branch")
    if repo_key(company, repo) != task["project"]:
        refuse(f"the active task is for {task['project']}")
    if kind == "github":
        head = one(args, ("--head",), ("-H",), "--head")
        if head != task["branch"]:
            refuse(f"pr create needs --head {task['branch']} (the task's branch)")
        if has_flag(args, "--web", "-w"):
            refuse("--web is not allowed")
    else:
        source = one(args, ("--source-branch",), ("-s",), "--source-branch")
        if source != task["branch"]:
            refuse(f"mr create needs --source-branch {task['branch']} (the task's branch)")
        if has_flag(args, "--head", "--create-source-branch", "--web", "-w"):
            refuse("forks, --create-source-branch and --web are not allowed")
        pushes = [arg for arg in args if arg == "--push" or arg.startswith("--push=")]
        if (pushes or has_flag(args, "--fill", "-f")) and (not pushes or set(pushes) != {"--push=false"}):
            refuse("mr create must not push; push with git, then pass --push=false")


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
