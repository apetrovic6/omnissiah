"""The one-time stygies workspace move (modules/rites/_hermes-workspace-migrate.py) on a scratch home."""

import fcntl
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from tempfile import TemporaryDirectory

SCRIPT = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-workspace-migrate.py"
COMPANIES = ("devzero", "codilas")
ROW = "2026-11-25T10:00:00+00:00\t!room:example.org\t$t\ttally\tpending\tA task\n"


def load():
    spec = importlib.util.spec_from_file_location("hermes_workspace_migrate", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


migrate = load()


def snapshot(root):
    """Every path below root: directories, file bytes and symlink targets."""
    tree = {}
    for path in sorted(root.rglob("*")):
        key = str(path.relative_to(root))
        if path.is_symlink():
            tree[key] = ("link", os.readlink(path))
        elif path.is_dir():
            tree[key] = ("dir", None)
        else:
            tree[key] = ("file", path.read_bytes())
    return tree


def write(path, text=""):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class WorkspaceMigration(unittest.TestCase):
    def setUp(self):
        self.home = Path(self.enterContext(TemporaryDirectory()))

    def old_layout(self):
        h = self.home
        write(h / "work/rust-app-template/.git/HEAD", "ref: refs/heads/main\n")
        write(h / "work/rust-app-template/src/main.rs", "fn main() {}\n")
        write(h / "work/tally/README.md", "tally\n")
        write(h / "work/.task-queue", ROW)
        write(h / "work/.task-lock")
        write(h / "work/.current-task")
        write(h / "work-devzero/devzero/nautili/.git/HEAD", "ref: refs/heads/feature/INF-423-credit-admin-actions\n")
        (h / "work-devzero/codilas").mkdir(parents=True)
        write(h / "work-devzero/.tasks/devzero/.task-lock")
        write(h / "work-devzero/.tasks/devzero/.current-task")
        write(h / "work-devzero/.tasks/codilas/.task-queue", ROW)

    def tmpfiles_skeleton(self):
        """What the new tmpfiles rules create when activation did not move anything."""
        for path in ("personal", "work/.tasks", "work/devzero", "work/codilas"):
            (self.home / path).mkdir(parents=True, exist_ok=True)

    def run_migration(self, lock_wait=None):
        stderr = io.StringIO()
        saved = migrate.LOCK_WAIT
        if lock_wait is not None:
            migrate.LOCK_WAIT = lock_wait
        try:
            with redirect_stderr(stderr):
                status = migrate.main(["migrate", str(self.home), *COMPANIES])
        finally:
            migrate.LOCK_WAIT = saved
        return status, stderr.getvalue()

    def assert_new_layout(self, before):
        h = self.home
        self.assertFalse((h / "work-devzero").exists())
        self.assertEqual((h / "personal/rust-app-template/src/main.rs").read_text(), "fn main() {}\n")
        self.assertEqual((h / "personal/.task-queue").read_text(), ROW)
        self.assertEqual((h / "work/devzero/nautili/.git/HEAD").read_text(),
                         "ref: refs/heads/feature/INF-423-credit-admin-actions\n")
        self.assertEqual((h / "work/.tasks/codilas/.task-queue").read_text(), ROW)
        self.assertTrue((h / "work/codilas").is_dir())
        # Same files, only relocated; no tmpfiles skeleton dragged into ~/personal.
        moved = {}
        for key, value in before.items():
            if key.startswith("work-devzero/"):
                moved["work/" + key.removeprefix("work-devzero/")] = value
            elif key.startswith("work/"):
                moved["personal/" + key.removeprefix("work/")] = value
            elif key == "work-devzero":
                moved["work"] = value
            elif key == "work":
                moved["personal"] = value
        self.assertEqual(snapshot(h), moved)

    # --- the four required cases -----------------------------------------------------------

    def test_old_layout_moves_to_new(self):
        self.old_layout()
        before = snapshot(self.home)
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assert_new_layout(before)
        self.assertIn(f"moved {self.home}/work -> {self.home}/personal", log)
        self.assertIn(f"moved {self.home}/work-devzero -> {self.home}/work", log)

    def test_already_migrated_is_a_silent_no_op(self):
        self.old_layout()
        self.run_migration()
        after = snapshot(self.home)
        for _ in range(2):
            status, log = self.run_migration()
            self.assertEqual((status, log), (0, ""))
        self.assertEqual(snapshot(self.home), after)

    def test_ambiguous_states_refuse_untouched(self):
        cases = {
            "old personal ~/work and a non-empty ~/personal": lambda h: write(h / "personal/other/file", "x"),
            "company state in both ~/work-devzero and new ~/work": None,
            "a symlinked ~/personal": lambda h: (h / "personal").symlink_to(h / "work"),
        }
        for name, extra in cases.items():
            with self.subTest(name):
                shutil.rmtree(self.home)
                self.home.mkdir()
                if extra is None:
                    # Already-migrated layout, plus a stale ~/work-devzero with real content.
                    write(self.home / "personal/tally/README.md", "tally\n")
                    write(self.home / "work/devzero/nautili/.git/HEAD", "ref\n")
                    write(self.home / "work-devzero/devzero/nautili/.git/HEAD", "ref\n")
                else:
                    self.old_layout()
                    extra(self.home)
                before = snapshot(self.home)
                status, log = self.run_migration()
                self.assertEqual(status, migrate.REFUSED, log)
                self.assertIn("REFUSED, nothing changed", log)
                self.assertEqual(snapshot(self.home), before)

    def test_mixed_work_with_pending_company_move_refuses(self):
        self.old_layout()
        write(self.home / "work/devzero/stray", "x")  # personal repos and a company dir in one ~/work
        before = snapshot(self.home)
        status, log = self.run_migration()
        self.assertEqual(status, migrate.REFUSED)
        self.assertIn("holds both personal entries and company/.tasks entries", log)
        self.assertEqual(snapshot(self.home), before)

    def test_active_slots_refuse_untouched(self):
        for slot in ("work/.current-task", "work-devzero/.tasks/devzero/.current-task"):
            with self.subTest(slot=slot):
                shutil.rmtree(self.home)
                self.home.mkdir()
                self.old_layout()
                write(self.home / slot, ROW)
                before = snapshot(self.home)
                status, log = self.run_migration()
                self.assertEqual(status, migrate.REFUSED, log)
                self.assertIn(f"active task in {self.home / slot.removesuffix('/.current-task')}", log)
                self.assertEqual(snapshot(self.home), before)

    # --- robustness -----------------------------------------------------------------------

    def test_skeleton_left_by_tmpfiles_after_a_refused_run_is_ignored(self):
        self.old_layout()
        before = snapshot(self.home)
        self.tmpfiles_skeleton()  # empty ~/personal, and empty company dirs inside the OLD ~/work
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assert_new_layout(before)

    def test_held_slot_lock_refuses(self):
        self.old_layout()
        before = snapshot(self.home)
        with open(self.home / "work-devzero/.tasks/devzero/.task-lock", "rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            status, log = self.run_migration(lock_wait=0.3)
        self.assertEqual(status, migrate.REFUSED)
        self.assertIn("a task command holds", log)
        self.assertEqual(snapshot(self.home), before)

    def test_each_half_runs_on_its_own(self):
        # Only the company half pending (personal already moved, ~/work gone).
        write(self.home / "personal/tally/README.md", "tally\n")
        write(self.home / "work-devzero/.tasks/devzero/.task-queue", ROW)
        self.assertEqual(self.run_migration()[0], 0)
        self.assertEqual((self.home / "work/.tasks/devzero/.task-queue").read_text(), ROW)
        # Only the personal half pending, and an empty leftover ~/work-devzero gets removed.
        shutil.rmtree(self.home)
        self.home.mkdir()
        write(self.home / "work/tally/README.md", "tally\n")
        (self.home / "work-devzero/.tasks").mkdir(parents=True)
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assertEqual((self.home / "personal/tally/README.md").read_text(), "tally\n")
        self.assertFalse((self.home / "work").exists())
        self.assertFalse((self.home / "work-devzero").exists())

    def test_fresh_home_does_nothing(self):
        self.assertEqual(self.run_migration(), (0, ""))
        self.tmpfiles_skeleton()
        before = snapshot(self.home)
        self.assertEqual(self.run_migration(), (0, ""))
        self.assertEqual(snapshot(self.home), before)

    @unittest.skipIf(shutil.which("git") is None, "needs git")
    def test_linked_worktrees_follow_the_move(self):
        def git(*args):
            env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
                   "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.org",
                   "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.org"}
            return subprocess.run(["git", *args], capture_output=True, text=True, env=env, check=True).stdout

        old_personal, old_work = self.home / "work", self.home / "work-devzero"
        for repo, worktree in ((old_personal / "tally", old_personal / "tally-review"),
                               (old_work / "devzero/nautili", old_work / "devzero/nautili-INF-423")):
            repo.mkdir(parents=True)
            git("-C", str(repo), "init", "-q", "-b", "main")
            git("-C", str(repo), "commit", "-q", "--allow-empty", "-m", "init")
            git("-C", str(repo), "worktree", "add", "-q", "-b", "side", str(worktree))
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        for repo, worktree in ((self.home / "personal/tally", self.home / "personal/tally-review"),
                               (self.home / "work/devzero/nautili", self.home / "work/devzero/nautili-INF-423")):
            self.assertEqual(git("-C", str(worktree), "rev-parse", "--abbrev-ref", "HEAD").strip(), "side")
            listing = git("-C", str(repo), "worktree", "list", "--porcelain")
            self.assertIn(f"worktree {worktree}\n", listing)
            self.assertNotIn("prunable", listing)
            self.assertNotIn("work-devzero", (worktree / ".git").read_text())
        self.assertIn("updated", log)


if __name__ == "__main__":
    unittest.main()
