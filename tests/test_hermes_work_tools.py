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
FAKE_CLI = """#!{python} -I
import json, os, sys
keep = ("GH_", "GITHUB_", "GITLAB_", "GLAB_", "GL_", "DO_NOT_TRACK", "XDG_CONFIG_HOME")
print(json.dumps({{"argv": sys.argv, "env": {{k: v for k, v in os.environ.items() if k.startswith(keep)}}}}))
"""


def git(cwd, *args, **kwargs):
    env = {"PATH": os.environ["PATH"], "HOME": str(cwd), "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}
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
            self.companies[name] = {
                "kind": kind, "host": host, "repos": repos,
                "gitUsername": "x-access-token" if kind == "github" else "hermes",
                "tokenFile": str(token), "stateDir": str(state),
                "configDir": str(self.root / "config" / name), "cli": str(fake),
            }
        self.config = self.root / "config.json"
        self.write_config()
        self.env = {"PATH": os.environ["PATH"], "HOME": str(self.root),
                    "GH_TOKEN": "inherited", "GITHUB_TOKEN": "inherited", "GH_REPO": "evil/repo",
                    "GITLAB_TOKEN": "inherited", "GLAB_X": "1", "GL_HOST": "evil.example"}

    def write_config(self):
        self.config.write_text(json.dumps({"branchPattern": BRANCH_PATTERN, "companies": self.companies}))

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

    def test_guard_refuses_other_url_forms_and_repos_on_company_hosts(self):
        work = self.repo()
        self.set_task()
        for url in ("git@github.com:example-org/api.git", "ssh://git@github.com/example-org/api.git",
                    "http://github.com/example-org/api.git", "https://user:pw@github.com/example-org/api.git",
                    "https://github.com:443/example-org/api.git", "https://GitHub.com/example-org/api.git?x=1"):
            with self.subTest(url=url):
                self.assertRefused(self.push(work, self.new_branch(), url=url), "must use https://")
        self.assertRefused(self.push(work, self.new_branch(), url="https://github.com/other/repo.git"),
                           "is not an enabled devzero repo")

    def test_guard_ignores_other_hosts(self):
        work = self.repo()
        for url in ("ssh://forgejo@forge.example.org:2222/hermes/tally.git", "https://forge.example.org/hermes/x.git",
                    "/srv/git/x.git", "../local.git", "file:///srv/x.git"):
            with self.subTest(url=url):
                result = self.push(work, self.new_branch("main"), url=url)
                self.assertEqual((result.returncode, result.stderr), (0, ""))

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

    def test_cli_subcommand_allowlist(self):
        refused = [
            ("devzero", "pr", "merge", "--repo", "example-org/api", "1"),
            ("devzero", "pr", "close", "--repo", "example-org/api", "1"),
            ("devzero", "repo", "delete", "example-org/api"),
            ("devzero", "secret", "list"),
            ("devzero", "auth", "token"),
            ("devzero", "auth", "status", "--show-token"),
            ("devzero", "--repo", "example-org/api", "pr", "view"),
            ("codilas", "mr", "merge", "--repo", "example/group/backend", "1"),
            ("codilas", "mr", "approve", "--repo", "example/group/backend", "1"),
            ("codilas", "variable", "list"),
            ("codilas", "auth", "login"),
        ]
        for args in refused:
            with self.subTest(args=args):
                self.assertIn("refused by Hermes work wrapper", self.cli(*args, code=2))
        self.cli("devzero", "auth", "status")
        self.cli("codilas", "ci", "status", "--repo", "example/group/backend")
        self.cli("devzero", "repo", "view", "example-org/web")

    def test_cli_requires_an_enabled_repo(self):
        for args in (("pr", "view", "12"), ("pr", "view", "--repo", "other/repo"), ("pr", "view", "-R", "other/repo"),
                     ("pr", "view", "--repo=other/repo"), ("pr", "view", "--repo", "example-org/api", "--repo", "other/x"),
                     ("pr", "view", "-Rother/repo", "--repo", "example-org/api"), ("repo", "view"),
                     ("repo", "view", "other/repo"), ("pr", "view", "--hostname", "x", "--repo", "example-org/api")):
            with self.subTest(args=args):
                self.assertIn("refused", self.cli("devzero", *args, code=2))
        self.cli("devzero", "pr", "view", "-R", "example-org/api", "12")
        self.cli("devzero", "pr", "view", "--repo=example-org/api.git", "12")

    def test_cli_create_is_bound_to_the_active_task(self):
        create = ("pr", "create", "--repo", "example-org/api", "--base", "main", "--head", BRANCH, "--title", "t")
        self.assertIn("no active task", self.cli("devzero", *create, code=2))
        self.set_task()
        self.cli("devzero", *create)
        self.assertIn("--head", self.cli("devzero", *create[:-4], "--head", "feature/DEV-2-x", "--title", "t", code=2))
        self.assertIn("--head", self.cli("devzero", "pr", "create", "--repo", "example-org/api", "--title", "t", code=2))
        self.assertIn("is for api", self.cli("devzero", "pr", "create", "--repo", "example-org/web", "--head", BRANCH, code=2))
        self.assertIn("--web", self.cli("devzero", *create, "--web", code=2))

        mr = ("mr", "create", "--repo", "example/group/backend", "--source-branch", BRANCH,
              "--target-branch", "main", "--title", "t", "--yes")
        self.set_task("codilas", project="backend")
        self.cli("codilas", *mr)
        self.cli("codilas", *mr, "--push=false")
        self.cli("codilas", *mr, "--fill", "--push=false")
        for extra in (("--fill",), ("--push",), ("--push=true",), ("--push=false", "--push"), ("--head", "fork/x"),
                      ("--create-source-branch",), ("--web",)):
            with self.subTest(extra=extra):
                self.assertIn("refused", self.cli("codilas", *mr, *extra, code=2))
        self.assertIn("--source-branch", self.cli("codilas", *mr[:4], "--source-branch", "main", code=2))

    def test_cli_api_is_get_only(self):
        self.cli("devzero", "api", "repos/example-org/api/pulls/1/comments")
        self.cli("devzero", "api", "--method", "GET", "-F", "per_page=100", "repos/example-org/api/pulls")
        self.cli("codilas", "api", "-X", "GET", "projects/1/merge_requests/2/notes")
        for args in (("api", "-X", "POST", "repos/x"), ("api", "--method=PATCH", "repos/x"),
                     ("api", "-f", "body=x", "repos/x"), ("api", "--input", "f", "repos/x"),
                     ("api", "graphql", "-f", "query=x"), ("api", "-X", "GET", "graphql"),
                     ("api", "--hostname", "evil.example", "repos/x"), ("api",), ("api", "-XPOST", "repos/x")):
            with self.subTest(args=args):
                self.assertIn("refused", self.cli("devzero", *args, code=2))

    def test_cli_without_token_or_company_fails_clearly(self):
        Path(self.companies["devzero"]["tokenFile"]).unlink()
        result = self.run_tool("cli", "devzero", "auth", "status")
        self.assertEqual(result.returncode, 1)
        self.assertIn("token file missing", result.stderr)
        self.assertIn("not enabled", self.cli("nope", "auth", "status", code=2))


if __name__ == "__main__":
    unittest.main()
