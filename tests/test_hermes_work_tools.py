"""Exercise the work coder's credential helper, push guard and CLI wrapper without a forge."""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


TOOL = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-work-tools.py"
BRANCH_PATTERN = r"^(feature|fix|chore)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9][a-z0-9-]*$"
BRANCH = "feature/DEV-1-fix-login"
TOKEN = "test-token-not-real"
ZERO = "0" * 40
EMAIL = "dev@example.com"  # the test identity; never a real address
FAKE_CLI = """#!{python} -I
import json, os, sys
keep = ("GH_", "GITHUB_", "GITLAB_", "GLAB_", "GL_", "DO_NOT_TRACK", "XDG_CONFIG_HOME")
print(json.dumps({{"argv": sys.argv, "env": {{k: v for k, v in os.environ.items() if k.startswith(keep)}}}}))
"""


def git(cwd, *args, **kwargs):
    env = {"PATH": os.environ["PATH"], "HOME": str(cwd), "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": EMAIL,
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": EMAIL}
    env.update(kwargs.pop("env", {}))
    return subprocess.run(["git", *args], cwd=cwd, env=env, capture_output=True, text=True,
                          check=True, **kwargs).stdout.strip()


class WorkTools(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(TemporaryDirectory()))
        fake = self.root / "fake-cli"
        fake.write_text(FAKE_CLI.format(python=sys.executable))
        fake.chmod(0o755)
        self.companies = {}
        for name, kind, host, repos in (
            ("devzero", "github", "github.com", {"api": "example-org/api", "web": "example-org/web"}),
            ("codilas", "gitlab", "gitlab.example.com", {"backend": "example/group/backend"}),
        ):
            state = self.root / "tasks" / name
            state.mkdir(parents=True)
            token = self.root / f"{name}.token"
            token.write_text(TOKEN)  # Clan prompt files may lack a newline.
            identity = self.root / f"{name}.gitconfig"
            identity.write_text(f'[user]\n  name = "Ex Ample"\n  email = "{EMAIL}"\n')
            self.companies[name] = {
                "kind": kind, "host": host, "repos": repos,
                "gitUsername": "x-access-token" if kind == "github" else "hermes",
                "tokenFile": str(token), "identityFile": str(identity), "stateDir": str(state),
                "configDir": str(self.root / "config" / name), "cli": str(fake),
            }
        self.config = self.root / "config.json"
        self.write_config()
        self.env = {"PATH": os.environ["PATH"], "HOME": str(self.root),
                    "GH_TOKEN": "inherited", "GITHUB_TOKEN": "inherited", "GH_REPO": "evil/repo",
                    "GITLAB_TOKEN": "inherited", "GLAB_X": "1", "GL_HOST": "evil.example"}

    def write_config(self):
        self.config.write_text(json.dumps({"branchPattern": BRANCH_PATTERN, "companies": self.companies,
                                           "personalHosts": ["forge.example.org", "forge.lab.example"],
                                           "secretPaths": [str(self.root / "secrets")]}))

    def run_tool(self, *args, stdin="", cwd=None, code=None):
        result = subprocess.run([sys.executable, "-I", "-B", str(TOOL), str(self.config), *args],
                                input=stdin, capture_output=True, text=True, env=self.env,
                                cwd=cwd or self.root, timeout=20, check=False)
        if code is not None:
            self.assertEqual(result.returncode, code, result.stderr)
        return result

    def set_task(self, company="devzero", project="api", branch=BRANCH):
        state = Path(self.companies[company]["stateDir"]) / ".current-task"
        state.write_text("\t".join(("2026-01-01T00:00:00Z", "!room:example.org", "$t", project, branch, "DEV-1")) + "\n")

    # --- credential helper --------------------------------------------------

    def fill(self, company="devzero", **fields):
        lines = "".join(f"{key}={value}\n" for key, value in fields.items()) + "\n"
        return self.run_tool("credential", company, "get", stdin=lines, code=0).stdout

    def test_credential_answers_only_listed_repos_on_the_exact_host(self):
        expected = f"username=x-access-token\npassword={TOKEN}\n\n"
        for path in ("example-org/api.git", "example-org/api", "example-org/web.git"):
            with self.subTest(path=path):
                self.assertEqual(self.fill(protocol="https", host="github.com", path=path), expected)
        self.assertEqual(self.fill("codilas", protocol="https", host="gitlab.example.com",
                                   path="example/group/backend.git"),
                         f"username=hermes\npassword={TOKEN}\n\n")
        refused = [
            dict(protocol="https", host="github.com"),  # no path: useHttpPath missing
            dict(protocol="http", host="github.com", path="example-org/api.git"),
            dict(protocol="https", host="github.com.evil.example", path="example-org/api.git"),
            dict(protocol="https", host="github.com:443", path="example-org/api.git"),
            dict(protocol="https", host="GITHUB.COM", path="example-org/api.git"),
            dict(protocol="https", host="github.com", path="example-org/api-evil.git"),
            dict(protocol="https", host="github.com", path="example-org/api.git/x"),
            dict(protocol="https", host="github.com", path="example-org/../example-org/api.git"),
            dict(protocol="https", host="github.com", path="Example-org/api.git"),
            dict(protocol="https", host="github.com", path="example-org/api.git", username="someone"),
            dict(protocol="https", host="gitlab.example.com", path="example-org/api.git"),
        ]
        for fields in refused:
            with self.subTest(fields=fields):
                self.assertEqual(self.fill(**fields), "")

    def test_credential_refuses_odd_input_and_other_operations(self):
        good = "protocol=https\nhost=github.com\npath=example-org/api.git\n"
        for stdin in (good + "host=github.com\n\n", good + "not a field\n\n", good.replace("path=", "path=x\npath=") + "\n"):
            with self.subTest(stdin=stdin):
                self.assertEqual(self.run_tool("credential", "devzero", "get", stdin=stdin, code=0).stdout, "")
        # Git 2.41+ sends capability/wwwauth lines, some repeated.
        extra = good + "capability[]=authtype\nwwwauth[]=Basic a\nwwwauth[]=Basic b\n\n"
        self.assertIn("password=", self.run_tool("credential", "devzero", "get", stdin=extra, code=0).stdout)
        for operation in ("store", "erase"):
            self.assertEqual(self.run_tool("credential", "devzero", operation, stdin=good + "\n", code=0).stdout, "")
        self.assertEqual(self.run_tool("credential", "nope", "get", stdin=good + "\n", code=0).stdout, "")

    def test_credential_without_token_answers_nothing(self):
        for content in ("", None):
            with self.subTest(content=content):
                token = Path(self.companies["devzero"]["tokenFile"])
                if content is None:
                    token.unlink()
                else:
                    token.write_text(content)
                self.assertEqual(self.fill(protocol="https", host="github.com", path="example-org/api.git"), "")

    def test_credential_through_git(self):
        helper = f"{sys.executable} -I -B {TOOL} {self.config} credential devzero"
        for url, expected in (("https://github.com/example-org/api.git", TOKEN), ("https://github.com/example-org/web", TOKEN),
                              ("https://github.com/other/repo.git", None)):
            with self.subTest(url=url):
                result = subprocess.run(
                    ["git", "-c", "credential.interactive=false",
                     "-c", f"credential.https://github.com/example-org/api.git.helper={helper}",
                     "-c", "credential.https://github.com/example-org/api.git.useHttpPath=true",
                     "-c", f"credential.https://github.com/example-org/web.helper={helper}",
                     "-c", "credential.https://github.com/example-org/web.useHttpPath=true",
                     "credential", "fill"],
                    input=f"url={url}\n\n", capture_output=True, text=True, timeout=20, check=False,
                    env={"PATH": os.environ["PATH"], "HOME": str(self.root), "GIT_CONFIG_NOSYSTEM": "1",
                         "GIT_TERMINAL_PROMPT": "0"},
                )
                if expected:
                    self.assertIn(f"password={expected}\n", result.stdout)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("password=", result.stdout)

    # --- pre-push guard -----------------------------------------------------

    def repo(self, url="https://github.com/example-org/api.git", default="main"):
        work = self.root / "repo"
        work.mkdir()
        git(work, "init", "-q", "-b", default)
        git(work, "remote", "add", "origin", url)
        git(work, "commit", "-q", "--allow-empty", "-m", "base")
        self.base = git(work, "rev-parse", "HEAD")
        git(work, "update-ref", f"refs/remotes/origin/{default}", self.base)
        git(work, "symbolic-ref", "refs/remotes/origin/HEAD", f"refs/remotes/origin/{default}")
        git(work, "switch", "-q", "-C", BRANCH)
        git(work, "commit", "-q", "--allow-empty", "-m", "work")
        self.head = git(work, "rev-parse", "HEAD")
        return work

    def push(self, work, *lines, url="https://github.com/example-org/api.git", remote="origin"):
        stdin = "".join(" ".join(line) + "\n" for line in lines)
        return self.run_tool("pre-push", remote, url, stdin=stdin, cwd=work)

    def new_branch(self, ref=BRANCH, local=None):
        return (f"refs/heads/{BRANCH}", local or self.head, f"refs/heads/{ref}", ZERO)

    def assertRefused(self, result, text):
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("refused by Hermes push guard", result.stderr)
        self.assertIn(text, result.stderr)

    def test_guard_allows_only_the_active_tasks_branch(self):
        work = self.repo()
        self.set_task()
        self.assertEqual(self.push(work, self.new_branch()).returncode, 0)
        # Fast-forward of the same branch (review follow-up adds commits).
        ff = (f"refs/heads/{BRANCH}", self.head, f"refs/heads/{BRANCH}", self.base)
        self.assertEqual(self.push(work, ff).returncode, 0)
        self.assertEqual(self.push(work).returncode, 0)  # nothing to push
        for ref in ("main", "feature/DEV-2-other", "hermes/x", f"{BRANCH}-x"):
            with self.subTest(ref=ref):
                self.assertRefused(self.push(work, self.new_branch(ref)), "may be pushed")
        tag = (f"refs/tags/v1", self.head, "refs/tags/v1", ZERO)
        self.assertRefused(self.push(work, tag), "may be pushed")
        two = (self.new_branch(), self.new_branch("main"))
        self.assertRefused(self.push(work, *two), "may be pushed")

    def test_guard_refuses_deletes_force_pushes_and_unknown_remote_tips(self):
        work = self.repo()
        self.set_task()
        delete = ("(delete)", ZERO, f"refs/heads/{BRANCH}", self.head)
        self.assertRefused(self.push(work, delete), "deleting")
        git(work, "switch", "-q", "--detach", self.base)
        git(work, "commit", "-q", "--allow-empty", "-m", "rewritten")
        rewritten = git(work, "rev-parse", "HEAD")
        force = (f"refs/heads/{BRANCH}", rewritten, f"refs/heads/{BRANCH}", self.head)
        self.assertRefused(self.push(work, force), "non-fast-forward")
        unknown = (f"refs/heads/{BRANCH}", self.head, f"refs/heads/{BRANCH}", "1" * 40)
        self.assertRefused(self.push(work, unknown), "fetch first")
        self.assertRefused(self.push(work, (f"refs/heads/{BRANCH}", self.head, f"refs/heads/{BRANCH}")), "unexpected")

    def test_guard_needs_an_active_task_for_this_repo_with_a_valid_branch(self):
        work = self.repo()
        self.assertRefused(self.push(work, self.new_branch()), "no active devzero task")
        self.set_task(branch="pending")
        self.assertRefused(self.push(work, self.new_branch()), "no active devzero task")
        self.set_task(project="web")
        self.assertRefused(self.push(work, self.new_branch()), "is for web, not api")
        self.set_task(branch="hermes/x")
        self.assertRefused(self.push(work, self.new_branch("hermes/x")), "naming rule")
        state = Path(self.companies["devzero"]["stateDir"]) / ".current-task"
        state.write_text("garbage\n")
        self.assertRefused(self.push(work, self.new_branch()), "task state is invalid")
        # Another company's slot never authorises this one.
        state.unlink()
        self.set_task("codilas", project="backend")
        self.assertRefused(self.push(work, self.new_branch()), "no active devzero task")

    def test_guard_refuses_the_default_branch_even_if_recorded(self):
        work = self.repo(default=BRANCH)
        self.set_task()
        self.assertRefused(self.push(work, self.new_branch()), "is the default branch")

    def test_guard_needs_a_known_default_branch_on_a_named_remote(self):
        work = self.repo()
        self.set_task()
        url = "https://github.com/example-org/api.git"
        self.assertRefused(self.push(work, self.new_branch(), remote=url), "unknown default branch")
        git(work, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
        self.assertRefused(self.push(work, self.new_branch()), "unknown default branch")

    def test_guard_accepts_only_the_two_rendered_url_forms(self):
        work = self.repo()
        self.set_task()
        for url in ("https://github.com/example-org/api.git", "https://github.com/example-org/api"):
            with self.subTest(accepted=url):
                self.assertEqual(self.push(work, self.new_branch(), url=url).returncode, 0)
        # S6: a trailing slash (or any other spelling) misses the includeIf, so the identity wouldn't apply.
        for url in ("https://github.com/example-org/api.git/", "https://github.com/example-org/api/",
                    "https://github.com/example-org/Api.git", "https://github.com//example-org/api.git",
                    "git@github.com:example-org/api.git", "ssh://git@github.com/example-org/api.git",
                    "http://github.com/example-org/api.git", "https://user:pw@github.com/example-org/api.git",
                    "https://github.com:443/example-org/api.git", "https://GitHub.com/example-org/api.git?x=1",
                    "https://github.com/example-org/api.git#x", "https://github.com/other/repo.git"):
            with self.subTest(refused=url):
                self.assertRefused(self.push(work, self.new_branch(), url=url), "must use a listed repo")

    def test_guard_requires_the_company_identity_on_every_pushed_commit(self):
        work = self.repo()
        self.set_task()
        # The base commit is on the remote already; only new commits are checked.
        git(work, "commit", "-q", "--allow-empty", "-m", "other author",
            env={"GIT_AUTHOR_EMAIL": "hermes@forge.lab.example"})
        other = git(work, "rev-parse", "HEAD")
        self.assertRefused(self.push(work, self.new_branch(local=other)), "identity")
        git(work, "commit", "-q", "--allow-empty", "-m", "other committer",
            env={"GIT_COMMITTER_EMAIL": "someone@example.net"})
        self.assertRefused(self.push(work, self.new_branch(local=git(work, "rev-parse", "HEAD"))), "identity")
        # Fast-forward range: only commits after the remote tip.
        git(work, "reset", "-q", "--hard", self.head)
        git(work, "commit", "-q", "--allow-empty", "-m", "good follow-up")
        ff = (f"refs/heads/{BRANCH}", git(work, "rev-parse", "HEAD"), f"refs/heads/{BRANCH}", self.head)
        self.assertEqual(self.push(work, ff).returncode, 0)
        ff_bad = (f"refs/heads/{BRANCH}", other, f"refs/heads/{BRANCH}", self.head)
        self.assertRefused(self.push(work, ff_bad), "identity")
        # Case of the address doesn't matter.
        git(work, "commit", "-q", "--allow-empty", "-m", "case", env={"GIT_AUTHOR_EMAIL": EMAIL.upper()})
        self.assertEqual(self.push(work, self.new_branch(local=git(work, "rev-parse", "HEAD"))).returncode, 0)

    def test_guard_allows_merging_the_default_branch_into_a_pushed_branch(self):
        # N1: the branch has a PR already; main moved on with a colleague's commit.
        work = self.repo()
        self.set_task()
        git(work, "update-ref", f"refs/remotes/origin/{BRANCH}", self.head)
        git(work, "switch", "-q", "--detach", self.base)
        git(work, "commit", "-q", "--allow-empty", "-m", "colleague",
            env={"GIT_AUTHOR_EMAIL": "colleague@example.org", "GIT_COMMITTER_EMAIL": "colleague@example.org"})
        git(work, "update-ref", "refs/remotes/origin/main", git(work, "rev-parse", "HEAD"))
        git(work, "switch", "-q", BRANCH)
        git(work, "merge", "-q", "--no-edit", "--no-ff", "origin/main")
        merge = git(work, "rev-parse", "HEAD")
        line = (f"refs/heads/{BRANCH}", merge, f"refs/heads/{BRANCH}", self.head)
        result = self.push(work, line)
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        # A new own commit with the wrong identity on top is still refused.
        git(work, "commit", "-q", "--allow-empty", "-m", "wrong", env={"GIT_AUTHOR_EMAIL": "hermes@forge.lab.example"})
        line = (f"refs/heads/{BRANCH}", git(work, "rev-parse", "HEAD"), f"refs/heads/{BRANCH}", self.head)
        self.assertRefused(self.push(work, line), "identity")

    def test_guard_refuses_empty_emails(self):
        # N2: git allows author=<> committer=<>; an empty field must not be skipped.
        work = self.repo()
        self.set_task()
        for env in ({"GIT_AUTHOR_EMAIL": ""}, {"GIT_COMMITTER_EMAIL": ""},
                    {"GIT_AUTHOR_EMAIL": "", "GIT_COMMITTER_EMAIL": ""}):
            with self.subTest(env=env):
                git(work, "reset", "-q", "--hard", self.head)
                git(work, "commit", "-q", "--allow-empty", "-m", "empty", env=env)
                fields = git(work, "log", "-1", "--format=%ae|%ce")
                self.assertIn("|", fields)
                self.assertIn("", fields.split("|"))
                self.assertRefused(self.push(work, self.new_branch(local=git(work, "rev-parse", "HEAD"))), "empty")

    def test_guard_refuses_without_an_identity_file(self):
        work = self.repo()
        self.set_task()
        identity = Path(self.companies["devzero"]["identityFile"])
        for content in ("", '[user]\n  name = "x"\n', None):
            with self.subTest(content=content):
                if content is None:
                    identity.unlink()
                else:
                    identity.write_text(content)
                self.assertRefused(self.push(work, self.new_branch()), "identity file is missing or empty")

    def test_guard_passes_personal_forges_and_local_urls(self):
        work = self.repo()
        for url in ("ssh://forgejo@forge.lab.example:2222/hermes/tally.git", "https://forge.example.org/hermes/x.git",
                    "ssh://git@elsewhere.example/x.git", "/srv/git/x.git", "../local.git", "file:///srv/x.git"):
            with self.subTest(url=url):
                result = self.push(work, self.new_branch("main"), url=url)
                self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_guard_fails_closed_for_unknown_http_hosts(self):
        # S5: e.g. www.github.com could redirect to a listed repo and get its token.
        work = self.repo()
        self.set_task()
        for url in ("https://www.github.com/example-org/api.git", "https://evil.example/x.git",
                    "http://forge.example.org.evil/x.git", "HTTPS://evil.example/x.git"):
            with self.subTest(url=url):
                self.assertRefused(self.push(work, self.new_branch(), url=url), "neither a company nor a personal forge")

    def test_guard_runs_as_a_config_hook_on_push(self):
        # The installed shape: a global `hook.<name>` entry, Git appending the hook arguments.
        work = self.repo()
        bare = self.root / "bare.git"
        git(self.root, "init", "-q", "--bare", str(bare))
        git(work, "remote", "add", "local", str(bare))
        hook = f"{sys.executable} -I -B {TOOL} {self.config} pre-push"
        git(work, "config", "hook.hermes-work-guard.event", "pre-push")
        git(work, "config", "hook.hermes-work-guard.command", hook)
        git(work, "push", "-q", "local", f"{BRANCH}:main")  # a non-company remote passes untouched
        self.assertEqual(git(bare, "rev-parse", "main"), self.head)
        # A company host is judged by the URL Git really pushes to: fake the ssh
        # transport into the local bare repo, so pre-push runs for github.com.
        fake_ssh = self.root / "fake-ssh"
        fake_ssh.write_text(f"#!/bin/sh\nexec git receive-pack {bare}\n")
        fake_ssh.chmod(0o755)
        git(work, "remote", "add", "company", "ssh://git@github.com/example-org/api.git")
        git(work, "config", "core.sshCommand", str(fake_ssh))
        self.set_task()
        result = subprocess.run(["git", "push", "company", f"{BRANCH}:refs/heads/{BRANCH}"], cwd=work,
                                capture_output=True, text=True, timeout=20, check=False,
                                env={"PATH": os.environ["PATH"], "HOME": str(self.root), "GIT_CONFIG_NOSYSTEM": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refused by Hermes push guard", result.stderr)
        self.assertEqual(git(bare, "for-each-ref", "--format=%(refname)"), "refs/heads/main")
        # Without the hook the same transport works, so the refusal was the guard's.
        git(work, "push", "-q", "--no-verify", "company", f"{BRANCH}:refs/heads/{BRANCH}")
        self.assertEqual(git(bare, "rev-parse", BRANCH), self.head)

    # --- CLI wrapper --------------------------------------------------------

    def cli(self, company, *args, code=0):
        result = self.run_tool("cli", company, *args)
        self.assertEqual(result.returncode, code, result.stderr)
        return json.loads(result.stdout) if code == 0 else result.stderr

    def refused(self, company, *args):
        self.assertIn("refused by Hermes work wrapper", self.cli(company, *args, code=2))

    def test_cli_injects_the_token_only_into_the_child_env(self):
        out = self.cli("devzero", "pr", "view", "--repo", "example-org/api", "12")
        self.assertEqual(out["argv"][1:], ["pr", "view", "--repo", "example-org/api", "12"])
        self.assertNotIn(TOKEN, out["argv"])
        self.assertEqual(out["env"], {
            "GH_TOKEN": TOKEN, "GH_HOST": "github.com", "GH_CONFIG_DIR": self.companies["devzero"]["configDir"],
            "GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "GH_NO_EXTENSION_UPDATE_NOTIFIER": "1",
            "GH_TELEMETRY": "0", "GH_SPINNER_DISABLED": "1", "DO_NOT_TRACK": "1",
        })
        out = self.cli("codilas", "mr", "list", "--repo", "example/group/backend")
        self.assertEqual(out["env"], {
            "GITLAB_TOKEN": TOKEN, "GITLAB_HOST": "gitlab.example.com", "GLAB_SEND_TELEMETRY": "0",
            "GLAB_CHECK_UPDATE": "false", "GLAB_NO_PROMPT": "1", "DO_NOT_TRACK": "1",
        })

    def test_cli_auth_check_is_api_user(self):
        # F4: glab has no stored login, so `auth status` can't pass; `api user` works for both.
        self.cli("devzero", "api", "user")
        self.cli("codilas", "api", "user")
        self.refused("devzero", "auth", "status")
        self.refused("codilas", "auth", "status")

    def test_cli_refuses_unlisted_commands_flags_and_forms(self):
        for company, *args in (
            ("devzero", "pr", "merge", "--repo", "example-org/api", "1"),
            ("devzero", "pr", "close", "--repo", "example-org/api", "1"),
            ("devzero", "repo", "delete", "example-org/api"),
            ("devzero", "secret", "list"),
            ("devzero", "auth", "token"),
            ("devzero", "--repo", "example-org/api", "pr", "view"),
            ("devzero", "pr", "view", "--repo", "example-org/api", "--web"),
            ("devzero", "pr", "view", "--repo", "example-org/api", "--template", "{{.}}"),
            ("codilas", "mr", "merge", "--repo", "example/group/backend", "1"),
            ("codilas", "mr", "approve", "--repo", "example/group/backend", "1"),
            ("codilas", "mr", "create", "--fill", "--repo", "example/group/backend"),
            ("codilas", "variable", "list"),
            ("codilas", "auth", "login"),
            # Short-flag bundles and attached values could hide a value flag.
            ("devzero", "pr", "view", "-cR", "other/repo"),
            ("devzero", "pr", "view", "-Rother/repo"),
            ("devzero", "pr", "view", "-R=other/repo"),
            # Duplicates (pflag keeps the last).
            ("devzero", "pr", "view", "--repo", "example-org/api", "--repo", "example-org/api"),
            # Positional counts.
            ("devzero", "pr", "list", "--repo", "example-org/api", "extra"),
            ("devzero", "pr", "view", "--repo", "example-org/api", "1", "2"),
            # Bool values only true/false.
            ("devzero", "pr", "view", "--repo", "example-org/api", "--comments=yes"),
        ):
            with self.subTest(args=args):
                self.refused(company, *args)

    def test_cli_bare_double_dash_is_refused_anywhere(self):
        # S4: pflag lets a value-taking option consume `--`, then keeps parsing.
        for company, *args in (
            ("devzero", "api", "repos/example-org/api/pulls/1/merge", "--jq", "--", "--method", "PUT"),
            ("codilas", "api", "projects/example%2Fgroup%2Fbackend/merge_requests/1/merge", "--method", "GET",
             "--input", "--", "--method", "PUT"),
            ("devzero", "pr", "comment", BRANCH, "--repo", "example-org/api", "--body", "--",
             "--repo", "victim-org/secret", "--body", "pwned"),
            ("codilas", "mr", "note", "create", BRANCH, "--repo", "example/group/backend", "--message", "--",
             "--repo", "victim/proj", "--message", "pwned"),
            ("devzero", "pr", "view", "--repo", "example-org/api", "--", "12"),
            ("devzero", "pr", "view", "--repo", "example-org/api", "--json", "--"),
        ):
            with self.subTest(args=args):
                self.set_task("devzero")
                self.set_task("codilas", project="backend")
                self.refused(company, *args)

    def test_cli_option_values_may_start_with_a_dash(self):
        # F7: a Markdown body starting with a bullet is a value, not a flag.
        self.set_task("codilas", project="backend")
        mr = ("mr", "create", "--repo", "example/group/backend", "--source-branch", BRANCH,
              "--target-branch", "main", "--title", "t", "--push=false", "--yes")
        out = self.cli("codilas", *mr, "--description", "- Fixed login\n- Tests")
        self.assertIn("- Fixed login\n- Tests", out["argv"])
        self.cli("codilas", *mr, "--description-file", "body.md")
        self.set_task("devzero")
        self.cli("devzero", "pr", "comment", BRANCH, "--repo", "example-org/api", "--body", "--repo other/x")

    def test_cli_requires_an_enabled_repo(self):
        for args in (("pr", "view", "12"), ("pr", "view", "--repo", "other/repo"), ("pr", "view", "-R", "other/repo"),
                     ("pr", "view", "--repo=other/repo"), ("repo", "view"), ("repo", "view", "other/repo"),
                     ("pr", "view", "--hostname", "x", "--repo", "example-org/api")):
            with self.subTest(args=args):
                self.refused("devzero", *args)
        self.cli("devzero", "pr", "view", "-R", "example-org/api", "12")
        self.cli("devzero", "pr", "view", "--repo=example-org/api.git", "12")
        self.cli("devzero", "repo", "view", "example-org/web")
        self.cli("codilas", "ci", "status", "--repo", "example/group/backend")

    def test_cli_create_is_bound_to_the_active_task(self):
        create = ("pr", "create", "--repo", "example-org/api", "--base", "main", "--head", BRANCH, "--title", "t")
        self.assertIn("active task", self.cli("devzero", *create, code=2))
        self.set_task()
        self.cli("devzero", *create)
        self.cli("devzero", *create, "--body-file", "body.md", "--draft")
        self.assertIn("--head", self.cli("devzero", *create[:-4], "--head", "feature/DEV-2-x", "--title", "t", code=2))
        self.assertIn("--head", self.cli("devzero", "pr", "create", "--repo", "example-org/api", "--title", "t", code=2))
        self.assertIn("is for api", self.cli("devzero", "pr", "create", "--repo", "example-org/web", "--head", BRANCH,
                                             code=2))
        for extra in (("--web",), ("--fill",), ("--reviewer", "x"), ("--dry-run",)):
            with self.subTest(gh=extra):
                self.refused("devzero", *create, *extra)

        mr = ("mr", "create", "--repo", "example/group/backend", "--source-branch", BRANCH,
              "--target-branch", "main", "--title", "t", "--yes")
        self.set_task("codilas", project="backend")
        self.cli("codilas", *mr)
        self.cli("codilas", *mr, "--push=false")
        # S3 (auto-merge) and the other unlisted mr create flags.
        for extra in (("--auto-merge",), ("--auto-merge=true",), ("--fill",), ("--push",), ("--push=true",),
                      ("--head", "fork/x"), ("--create-source-branch",), ("--web",), ("--remove-source-branch",),
                      ("--squash-before-merge",)):
            with self.subTest(glab=extra):
                self.refused("codilas", *mr, *extra)
        self.assertIn("--source-branch", self.cli("codilas", *mr[:4], "--source-branch", "main", code=2))

    def test_cli_writes_are_bound_to_the_active_task_and_its_branch(self):
        # S7: comment/edit/ready and note/update only on the task's own PR/MR, selected by branch.
        writes = {
            "devzero": [
                ("pr", "comment", BRANCH, "--repo", "example-org/api", "--body-file", "f"),
                ("pr", "edit", BRANCH, "--repo", "example-org/api", "--title", "t"),
                ("pr", "ready", BRANCH, "--repo", "example-org/api"),
            ],
            "codilas": [
                ("mr", "note", "create", BRANCH, "--repo", "example/group/backend", "--message", "m"),
                ("mr", "update", BRANCH, "--repo", "example/group/backend", "--title", "t"),
            ],
        }
        for company, commands in writes.items():
            for args in commands:
                with self.subTest(no_task=args):
                    self.assertIn("active task", self.cli(company, *args, code=2))
        self.set_task()
        self.set_task("codilas", project="backend")
        for company, commands in writes.items():
            for args in commands:
                with self.subTest(ok=args):
                    self.cli(company, *args)
                selector = args.index(BRANCH)
                for other in ("12", "feature/DEV-2-other", "main"):
                    with self.subTest(selector=other, args=args):
                        self.refused(company, *args[:selector], other, *args[selector + 1:])
        self.set_task(project="web")
        self.assertIn("is for web", self.cli("devzero", *writes["devzero"][0], code=2))

    def test_cli_no_inline_resolve_delete_or_retarget(self):
        self.set_task()
        self.set_task("codilas", project="backend")
        for company, *args in (
            ("devzero", "pr", "comment", BRANCH, "--repo", "example-org/api", "--delete-last"),
            ("devzero", "pr", "comment", BRANCH, "--repo", "example-org/api", "--edit-last", "--body", "x"),
            ("devzero", "pr", "ready", BRANCH, "--repo", "example-org/api", "--undo"),
            ("devzero", "pr", "edit", BRANCH, "--repo", "example-org/api", "--base", "other"),
            ("devzero", "pr", "edit", BRANCH, "--repo", "example-org/api", "--add-reviewer", "x"),
            ("codilas", "mr", "update", BRANCH, "--repo", "example/group/backend", "--target-branch", "other"),
            ("codilas", "mr", "update", BRANCH, "--repo", "example/group/backend", "--remove-source-branch"),
            ("codilas", "mr", "update", BRANCH, "--repo", "example/group/backend", "--lock-discussion"),
            ("codilas", "mr", "note", BRANCH, "--repo", "example/group/backend", "--message", "m"),
            ("codilas", "mr", "note", "delete", "1", BRANCH, "--repo", "example/group/backend"),
            ("codilas", "mr", "note", "resolve", "1", BRANCH, "--repo", "example/group/backend"),
            ("codilas", "mr", "note", "update", "1", BRANCH, "--repo", "example/group/backend"),
            ("codilas", "mr", "note", "draft", "create", BRANCH, "--repo", "example/group/backend"),
            ("codilas", "mr", "note", "create", BRANCH, "--repo", "example/group/backend", "--message", "m",
             "--reply", "abc"),
            ("codilas", "mr", "note", "create", BRANCH, "--repo", "example/group/backend", "--message", "m",
             "--line", "3"),
            ("codilas", "mr", "note", "create", "delete", BRANCH, "--repo", "example/group/backend", "--message", "m"),
        ):
            with self.subTest(args=args):
                self.refused(company, *args)

    def test_cli_api_endpoints_are_relative_and_under_listed_repos(self):
        for company, endpoint in (
            ("devzero", "repos/example-org/api"),
            ("devzero", "repos/example-org/api/pulls/1/comments"),
            ("devzero", "repos/example-org/api?per_page=100"),
            ("devzero", "repos/example-org/web/actions/runs"),
            ("codilas", "projects/example%2Fgroup%2Fbackend"),
            ("codilas", "projects/example%2Fgroup%2Fbackend/merge_requests/2/notes"),
        ):
            with self.subTest(allowed=endpoint):
                self.cli(company, "api", endpoint)
        for company, endpoint in (
            # S1: absolute URLs would carry the token to any host.
            ("codilas", "https://evil.example/api/v4/user"),
            ("devzero", "https://evil.example/x"),
            ("codilas", "/api/v4/user"),
            ("devzero", "/repos/example-org/api"),
            # S8: other repos, traversal, graphql, placeholders.
            ("devzero", "repos/other-org/private/contents/README.md"),
            ("devzero", "repos/example-org/api-evil"),
            ("devzero", "repos/example-org/api/../../other/x"),
            ("devzero", "repos/example-org/api/%2e%2e/%2e%2e/other/x"),
            ("devzero", "repos/example-org/api//x"),
            ("devzero", "graphql"),
            ("devzero", "/graphql?query=mutation"),
            ("devzero", "repos/example-org/api/%67raphql"),
            ("devzero", "repos/{owner}/{repo}/pulls"),
            ("devzero", "repos/example-org/api pulls"),
            ("codilas", "projects/:id/merge_requests"),
            ("codilas", "projects/:fullpath"),
            ("codilas", "projects/example/group/backend"),
            ("codilas", "projects/1/merge_requests"),
            ("codilas", "projects/example%2Fgroup%2Fbackend%2F..%2Fother"),
            ("codilas", "users"),
        ):
            with self.subTest(refused=endpoint):
                self.refused(company, "api", endpoint)

    def test_cli_api_is_get_only_with_listed_flags(self):
        repo = "repos/example-org/api/pulls"
        self.cli("devzero", "api", "--method", "GET", repo)
        self.cli("devzero", "api", "-X", "get", "--paginate", "--jq", ".[].number", "--include", repo)
        self.cli("devzero", "api", "--silent", "-H", "Accept: application/vnd.github.raw+json", repo)
        self.cli("codilas", "api", "--paginate", "--output", "ndjson", "projects/example%2Fgroup%2Fbackend/pipelines")
        for company, *args in (
            ("devzero", "api", "-X", "POST", repo),
            ("devzero", "api", "--method=PATCH", repo),
            ("devzero", "api", "--method", "GET", "--method", "PUT", repo),
            ("devzero", "api", "-f", "body=x", repo),
            ("devzero", "api", "-F", "x=1", "--method", "GET", repo),
            ("devzero", "api", "--field", "x=1", repo),
            ("devzero", "api", "--raw-field", "x=1", repo),
            ("devzero", "api", "--input", "f", repo),
            ("devzero", "api", "--hostname", "evil.example", repo),
            ("devzero", "api", "-H", "X-HTTP-Method-Override: PUT", repo),
            ("devzero", "api", "--jq", "env.GH_TOKEN", repo),
            ("devzero", "api", "--jq", "$ENV", repo),
            ("devzero", "api", "--cache", "1h", repo),
            ("devzero", "api"),
            # S2: --form switches glab to POST.
            ("codilas", "api", "projects/example%2Fgroup%2Fbackend/uploads", "--form", "file=@tok"),
            ("codilas", "api", "--placeholder", "x=y", "projects/example%2Fgroup%2Fbackend"),
            ("codilas", "api", "--jq", ".x", "projects/example%2Fgroup%2Fbackend"),
            ("codilas", "api", "-X", "DELETE", "projects/example%2Fgroup%2Fbackend"),
        ):
            with self.subTest(args=args):
                self.refused(company, *args)

    def test_cli_read_selectors_are_numbers_or_branch_names(self):
        # N3: a PR/MR URL as the selector would override --repo.
        reads = {
            "devzero": [("pr", "view"), ("pr", "diff"), ("pr", "checks"), ("run", "view"), ("run", "watch")],
            "codilas": [("mr", "view"), ("mr", "diff"), ("ci", "trace")],
        }
        repo = {"devzero": "example-org/api", "codilas": "example/group/backend"}
        refused = ("https://github.com/other-org/private/pull/1", "github.com/other-org/private/pull/1",
                   "https://gitlab.codilas.com/other/secret/-/merge_requests/1", "other/secret/-/merge_requests/1",
                   "gitlab.codilas.com/other/secret", "http://evil.example/x", "a..b", "x:y", "@{-1}", "a//b",
                   "-1", "feature/", "x.lock", "#1", "~1", "a b")
        for company, commands in reads.items():
            for words in commands:
                for selector in ("12", BRANCH, "main", "release/1.2"):
                    with self.subTest(allowed=(words, selector)):
                        self.cli(company, *words, selector, "--repo", repo[company])
                for selector in refused:
                    with self.subTest(refused=(words, selector)):
                        self.refused(company, *words, selector, "--repo", repo[company])

    def test_cli_api_refuses_extra_percent_encoding(self):
        for company, endpoint in (
            ("devzero", "repos/example-org/api/%252e%252e/%252e%252e/user"),
            ("devzero", "repos/example-org/api/contents/a%20b"),
            ("devzero", "repos/example-org/api?q=%41"),
            ("codilas", "projects/example%2Fgroup%2Fbackend/%252e%252e"),
            ("codilas", "projects/example%252Fgroup%252Fbackend"),
        ):
            with self.subTest(endpoint=endpoint):
                self.refused(company, "api", endpoint)
        self.cli("codilas", "api", "projects/example%2Fgroup%2Fbackend/merge_requests")

    def test_cli_body_files_must_not_be_secrets(self):
        self.set_task()
        self.set_task("codilas", project="backend")
        secrets = self.root / "secrets/vars/x"
        secrets.mkdir(parents=True)
        (secrets / "token").write_text("secret")
        (self.root / "link-to-token").symlink_to(self.companies["devzero"]["tokenFile"])
        (self.root / "link-to-secrets").symlink_to(secrets / "token")
        (self.root / "body.md").write_text("ok")
        bad = (str(secrets / "token"), self.companies["devzero"]["tokenFile"], self.companies["codilas"]["identityFile"],
               "link-to-token", "link-to-secrets", "secrets/vars/x/token", "./secrets/../secrets/vars/x/token",
               str(self.root / "secrets"))
        commands = (
            ("devzero", "pr", "create", "--repo", "example-org/api", "--head", BRANCH, "--title", "t", "--body-file"),
            ("devzero", "pr", "comment", BRANCH, "--repo", "example-org/api", "--body-file"),
            ("devzero", "pr", "edit", BRANCH, "--repo", "example-org/api", "-F"),
            ("codilas", "mr", "create", "--repo", "example/group/backend", "--source-branch", BRANCH,
             "--target-branch", "main", "--title", "t", "--yes", "--description-file"),
            ("codilas", "mr", "update", BRANCH, "--repo", "example/group/backend", "--description-file"),
        )
        for company, *args in commands:
            for path in bad:
                with self.subTest(args=args[:2], path=path):
                    self.assertIn("secret file", self.cli(company, *args, path, code=2))
            for path in ("body.md", "-", str(self.root / "body.md")):
                with self.subTest(args=args[:2], ok=path):
                    self.cli(company, *args, path)

    def test_cli_without_token_or_company_fails_clearly(self):
        Path(self.companies["devzero"]["tokenFile"]).unlink()
        result = self.run_tool("cli", "devzero", "api", "user")
        self.assertEqual(result.returncode, 1)
        self.assertIn("token file missing", result.stderr)
        self.assertIn("not enabled", self.cli("nope", "api", "user", code=2))


if __name__ == "__main__":
    unittest.main()
