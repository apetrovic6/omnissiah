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
in {
  launchers = tools.launcherTexts;
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
        (self.home / "work").mkdir()
        self.sentinel = self.home / "work/.current-task"
        self.sentinel.write_text("personal sentinel\n")
        self.bin = self.home / "bin"
        self.bin.mkdir()
        for company, text in data["launchers"].items():
            launcher = self.home / f"launcher-{company}"
            launcher.write_text(localise(text, self.home, data["home"]))
            for action in ("status", "claim", "branch", "done", "clear", "drop"):
                (self.bin / f"{company}-task-{action}").symlink_to(launcher)

    def run_task(self, command, *args, summary="", code=0):
        result = subprocess.run(
            [shutil.which("bash"), str(self.bin / command), *args], input=summary, capture_output=True, text=True,
            env={"PATH": os.environ["PATH"], "HOME": str(self.home)}, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def state(self, company):
        state = self.home / "work-devzero/.tasks" / company
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


if __name__ == "__main__":
    unittest.main()
