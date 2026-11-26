"""Run the Nix-rendered <company>-task-* launchers (not a hand-built env) against scratch state.

Evaluates stygies with both companies enabled (example repos) through
`extendModules`, takes the launcher text the module emits, relocates
/home/hermes to a temporary home, and runs it. Needs `nix` and the flake's
tracked files; skipped when `nix` is missing or HERMES_TEST_SKIP_NIX is set.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
TASK_SCRIPT = ROOT / "modules/rites/_hermes-task.py"
STORE = re.compile(r"/nix/store/[0-9a-z]{32}-[^\s/'\"]+(?:/[^\s'\"]*)?")
ENABLE = """
sys: let
  base = sys.config.services.imperium.hermesWork.companies;
  on = {
    devzero = base.devzero // { enabled = true; jiraProjects = ["DEV"]; repos = { api.path = "example-org/api"; web.path = "example-org/web"; }; };
    codilas = base.codilas // { enabled = true; repos.backend.path = "example/group/backend"; };
  };
  c = (sys.extendModules { modules = [{ services.imperium.hermesWork.companies = on; }]; }).config;
  tools = builtins.head (builtins.filter (p: p.name == "hermes-work-tools") c.users.users.hermes.packages);
  personal = builtins.head (builtins.filter (p: p.name == "hermes-task-tools") c.users.users.hermes.packages);
in {
  launchers = tools.launcherTexts;
  personal = personal.launcherText;
  rooms = builtins.mapAttrs (_: company: company.room) on;
  home = c.users.users.hermes.home;
}
"""
_rendered = None


def rendered():
    global _rendered
    if _rendered is None:
        result = subprocess.run(
            ["nix", "eval", "--json", f"{ROOT}#nixosConfigurations.stygies", "--apply", ENABLE],
            capture_output=True, text=True, timeout=600, check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr[-2000:])
        _rendered = json.loads(result.stdout)
    return _rendered


def localise(text, home, hermes_home):
    """Relocate the home; keep store paths that exist, else use local equivalents (no builds)."""
    def replace(match):
        path = match.group(0)
        if os.path.exists(path):
            return path
        name = os.path.basename(path)
        if name.endswith("_hermes-task.py"):
            return str(TASK_SCRIPT)
        if name.startswith("python3"):
            return sys.executable
        local = shutil.which(name)
        if local is None:
            raise unittest.SkipTest(f"{path} is not in the store and {name} is not on PATH")
        return local
    return STORE.sub(replace, text.replace(hermes_home, str(home)))


@unittest.skipIf(shutil.which("nix") is None or os.environ.get("HERMES_TEST_SKIP_NIX"), "needs nix")
class RenderedLaunchers(unittest.TestCase):
    def setUp(self):
        data = rendered()
        self.rooms = data["rooms"]
        self.home = Path(self.enterContext(TemporaryDirectory()))
        (self.home / "personal").mkdir()
        self.sentinel = self.home / "personal/.current-task"
        self.sentinel.write_text("personal sentinel\n")
        self.bin = self.home / "bin"
        self.bin.mkdir()
        personal = self.home / "launcher-personal"
        self.personal_text = data["personal"]
        self.company_texts = data["launchers"]
        personal.write_text(localise(data["personal"], self.home, data["home"]))
        for action in ("status", "claim", "branch", "done", "clear"):
            (self.bin / f"task-{action}").symlink_to(personal)
        for company, text in data["launchers"].items():
            launcher = self.home / f"launcher-{company}"
            launcher.write_text(localise(text, self.home, data["home"]))
            for action in ("status", "claim", "branch", "done", "clear", "drop"):
                (self.bin / f"{company}-task-{action}").symlink_to(launcher)

    def run_task(self, command, *args, summary="", code=0, env=None):
        result = subprocess.run(
            [shutil.which("bash"), str(self.bin / command), *args], input=summary, capture_output=True, text=True,
            env={"PATH": os.environ["PATH"], "HOME": str(self.home), **(env or {})}, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def state(self, company):
        state = self.home / "work/.tasks" / company
        # The launcher creates the lock file before the script runs; that's not task state.
        paths = state.iterdir() if state.exists() else ()
        return {path.name: path.read_bytes() for path in paths if path.name != ".task-lock"}

    def test_wrong_room_claims_are_rejected_without_state_change(self):
        for company, other in (("devzero", "codilas"), ("codilas", "devzero")):
            with self.subTest(company=company):
                repo = "api" if company == "devzero" else "backend"
                before = self.state(company)
                result = self.run_task(f"{company}-task-claim", "--", self.rooms[other], "$t", repo, "-",
                                       summary="wrong room", code=2)
                self.assertEqual(result.stderr, "This Matrix room does not use these task commands.\n")
                self.assertEqual(self.state(company), before)
                self.assertNotIn(".current-task", self.state(company))
        self.assertEqual(self.sentinel.read_text(), "personal sentinel\n")

    def test_rendered_slots_are_per_company_with_their_allowlists(self):
        claim = json.loads(self.run_task("devzero-task-claim", "--", self.rooms["devzero"], "$t1", "api", "-",
                                         summary="DEV-1 task").stdout)
        self.assertEqual(claim["result"], "claimed")
        self.assertEqual(self.state("codilas"), {})
        # Repos of the other company, or unlisted ones, are refused for Matrix and app claims.
        self.run_task("devzero-task-claim", "--", self.rooms["devzero"], "$t2", "backend", "-", summary="x", code=2)
        self.run_task("codilas-task-claim", "--app", "new", "--", "api", "-", summary="x", code=2)
        stamp = claim["active"]["started_at"]
        origin = ("--", self.rooms["devzero"], "$t1", stamp)
        self.run_task("devzero-task-branch", *origin, "hermes/x", code=2)
        updated = json.loads(self.run_task("devzero-task-branch", *origin, "feature/DEV-1-fix-login").stdout)
        self.assertEqual(updated["active"]["branch"], "feature/DEV-1-fix-login")
        app = json.loads(self.run_task("codilas-task-claim", "--app", "new", "--", "backend", "-",
                                       summary="COD-1").stdout)
        self.assertEqual(app["result"], "claimed")
        self.assertEqual(json.loads(self.run_task("devzero-task-done", *origin).stdout)["result"], "idle")
        self.assertIn(".current-task", self.state("codilas"))
        self.assertEqual(self.sentinel.read_text(), "personal sentinel\n")

    def test_personal_launcher_uses_personal_never_work(self):
        self.sentinel.unlink()  # not a valid task row; the personal commands would refuse it
        status = json.loads(self.run_task("task-status", "--all").stdout)
        self.assertEqual((status["tasks"], status["max_live"]), ([], 3))
        self.assertTrue((self.home / "personal/.task-lock").is_file())
        self.assertFalse((self.home / "work").exists())
        # Worktree mode: the script takes the lock itself, and claims go to ~/personal/.task-state.json.
        self.assertIn("export HERMES_TASK_MODE=worktrees", self.personal_text)
        self.assertNotIn("flock", self.personal_text)
        # An inherited slot or allowlist never reaches the personal commands.
        inherited = {"HERMES_TASK_STATE_DIR": str(self.home / "work/.tasks/devzero"), "HERMES_TASK_PROJECTS": "[]",
                     "HERMES_TASK_ROOMS": "[]", "HERMES_TASK_BRANCH_PATTERN": ".*"}
        claim = json.loads(self.run_task("task-claim", "--app", "new", "--", "tally", "-", summary="App task",
                                         env=inherited).stdout)
        self.assertEqual(claim["result"], "claimed")
        self.assertNotIn("worktree_path", claim)
        self.assertEqual(len(json.loads((self.home / "personal/.task-state.json").read_text())["tasks"]), 1)
        self.assertFalse((self.home / "work").exists())
        # Personal branches are hermes/<slug>: never the fork's default branch.
        origin = ("--app", claim["session_id"], "--", claim["active"]["started_at"])
        refused = self.run_task("task-branch", "--follow-up", *origin, "main", code=2, env=inherited)
        self.assertIn("does not match the required pattern", refused.stderr)
        for text in self.company_texts.values():
            self.assertIn("unset HERMES_TASK_MODE", text)

    def test_launchers_refuse_until_the_workspace_migration_ran(self):
        # The old personal slot still in ~/work: the personal commands refuse (the company ones too: R8b test).
        (self.home / "work").mkdir()
        for name in (".current-task", ".task-queue", ".task-lock"):
            with self.subTest(old=name):
                old = self.home / "work" / name
                old.write_text("")
                result = self.run_task("task-status", "--all", code=2)
                self.assertIn(f"workspace migration pending: ~/work/{name}", result.stderr)
                old.unlink()
        self.assertIn("ask manjo", result.stderr)  # the stray-file case never tells an agent to delete state
        # An empty ~/work-devzero (a stray mkdir) is not old state: the company commands work.
        (self.home / "work-devzero/.tasks/devzero").mkdir(parents=True)
        for company in ("devzero", "codilas"):
            self.run_task(f"{company}-task-status", "--queue")
        # Old files left in ~/work-devzero: every company command refuses without touching state.
        (self.home / "work-devzero/.tasks/devzero/.task-lock").write_text("")
        for company in ("devzero", "codilas"):
            with self.subTest(company=company):
                before = self.state(company)
                result = self.run_task(f"{company}-task-status", "--queue", code=2)
                self.assertIn("workspace migration pending: ~/work-devzero still holds files", result.stderr)
                self.assertEqual(self.state(company), before)
        self.assertEqual(self.sentinel.read_text(), "personal sentinel\n")


    def test_company_launchers_refuse_while_work_is_the_old_personal_tree(self):
        # A refused migration left the old personal tree in ~/work and only directories in ~/work-devzero:
        # a company slot must not be created among the personal repos.
        (self.home / "work-devzero/.tasks/devzero").mkdir(parents=True)
        (self.home / "work/tally").mkdir(parents=True)
        for name in (".current-task", ".task-queue", ".task-lock"):
            old = self.home / "work" / name
            old.write_text("")
            for company in ("devzero", "codilas"):
                with self.subTest(old=name, company=company):
                    result = self.run_task(f"{company}-task-status", "--queue", code=2)
                    self.assertIn(f"~/work/{name} is a personal task slot file", result.stderr)
                    self.assertIn("ask manjo", result.stderr)
            old.unlink()
        self.assertFalse((self.home / "work/.tasks").exists())
        # Gone: the company commands work again.
        self.run_task("devzero-task-status", "--queue")


if __name__ == "__main__":
    unittest.main()
