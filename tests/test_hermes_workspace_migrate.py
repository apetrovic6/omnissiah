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
    """Every path below root but the done-stamp's ~/.local: directories, file bytes, symlink targets."""
    tree = {}
    for path in sorted(root.rglob("*")):
        key = str(path.relative_to(root))
        if key == ".local" or key.startswith(".local/"):
            continue
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

    def stamped(self):
        return (self.home / migrate.STAMP).is_file()

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
        self.assertIn("moved; wrote", log)
        self.assertTrue(self.stamped())

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

    def test_fresh_home_does_nothing_but_stamp(self):
        self.tmpfiles_skeleton()
        before = snapshot(self.home)
        status, log = self.run_migration()
        self.assertEqual(status, 0)
        self.assertIn(f"no {self.home}/work-devzero: the new layout, nothing to move; wrote", log)
        self.assertEqual(self.run_migration(), (0, ""))  # the stamp: silent from now on
        self.assertEqual(snapshot(self.home), before)
        self.assertTrue(self.stamped())

    # --- fix round 1: the review's scenarios ------------------------------------------------

    def new_layout_scenario(self, name):
        """The review's scenarios 1, 1b, 1c: the new layout on a rebuilt VM, before any task command."""
        self.tmpfiles_skeleton()
        if name == "1":
            write(self.home / "work/notes.md", "work notes")
        elif name == "1b":
            write(self.home / "work/notes.md", "work notes")
            write(self.home / "work/.tasks/devzero/.task-lock")
        elif name == "1c":
            write(self.home / "work/nautili/.git/HEAD", "ref: refs/heads/main\n")

    def test_new_layout_without_old_evidence_is_never_moved(self):
        for name in ("1", "1b", "1c"):
            with self.subTest(scenario=name):
                shutil.rmtree(self.home)
                self.home.mkdir()
                self.new_layout_scenario(name)
                before = snapshot(self.home)
                status, log = self.run_migration()
                self.assertEqual(status, 0)
                self.assertIn("the new layout, nothing to move; wrote", log)  # one line, whenever it stamps
                self.assertEqual(self.run_migration(), (0, ""))
                self.assertEqual(snapshot(self.home), before)
                self.assertTrue(self.stamped())

    def test_stamp_ends_it_for_good(self):
        self.old_layout()
        self.assertEqual(self.run_migration()[0], 0)
        # A rollback's old generation recreates ~/work-devzero and writes a personal slot into ~/work.
        write(self.home / "work-devzero/.tasks/devzero/.task-lock")
        write(self.home / "work/.task-lock")
        before = snapshot(self.home)
        self.assertEqual(self.run_migration(), (0, ""))
        self.assertEqual(snapshot(self.home), before)

    def test_roll_forward_without_stamp_refuses_the_mixed_tree(self):
        # The review's scenario 2 with the stamp removed: ~/work mixes a stray personal slot and the company tree.
        write(self.home / "personal/tally/README.md", "x")
        write(self.home / "work/devzero/nautili/.git/HEAD", "x")
        write(self.home / "work/.tasks/devzero/.task-lock")
        write(self.home / "work/.task-lock")
        (self.home / "work-devzero/.tasks/devzero").mkdir(parents=True)
        before = snapshot(self.home)
        status, log = self.run_migration()
        self.assertEqual(status, migrate.REFUSED, log)
        self.assertEqual(snapshot(self.home), before)
        self.assertFalse(self.stamped())

    def test_stray_slot_file_next_to_populated_personal_refuses(self):
        # The review's scenario 7.
        write(self.home / "work/.task-lock")
        write(self.home / "personal/tally/x", "x")
        write(self.home / "work-devzero/devzero/nautili/.git/HEAD", "x")
        before = snapshot(self.home)
        self.assertEqual(self.run_migration()[0], migrate.REFUSED)
        self.assertEqual(snapshot(self.home), before)

    @unittest.skipIf(os.geteuid() == 0, "root reads everything")
    def test_unreadable_directory_refuses_before_any_move(self):
        # The review's scenarios 3 and 4: planning sees every directory, so nothing moves half-rewritten.
        self.old_layout()
        write(self.home / "work/tally/wt/.git", f"gitdir: {self.home}/work/tally/.git/worktrees/wt\n")
        write(self.home / "work/tally/.git/worktrees/wt/gitdir", f"{self.home}/work/tally/wt/.git\n")
        locked = self.home / "work/zzz-locked"
        write(locked / "f", "x")
        locked.chmod(0)
        try:
            status, log = self.run_migration()
        finally:
            locked.chmod(0o755)
        self.assertEqual(status, migrate.REFUSED, log)
        self.assertIn("cannot read the workspace", log)
        self.assertTrue((self.home / "work/tally/wt/.git").is_file())
        self.assertTrue((self.home / "work-devzero").is_dir())
        self.assertFalse((self.home / "personal").exists())
        # Readable again: the rerun moves and rewrites everything.
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assertEqual((self.home / "personal/tally/wt/.git").read_text(),
                         f"gitdir: {self.home}/personal/tally/.git/worktrees/wt\n")
        self.assertEqual((self.home / "personal/tally/.git/worktrees/wt/gitdir").read_text(),
                         f"{self.home}/personal/tally/wt/.git\n")

    def test_linked_worktree_outside_the_trees_is_repointed(self):
        # The review's scenario 5.
        self.old_layout()
        write(self.home / "wt/tally-fix/.git", f"gitdir: {self.home}/work/tally/.git/worktrees/tally-fix\n")
        write(self.home / "work/tally/.git/worktrees/tally-fix/gitdir", f"{self.home}/wt/tally-fix/.git\n")
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assertEqual((self.home / "wt/tally-fix/.git").read_text(),
                         f"gitdir: {self.home}/personal/tally/.git/worktrees/tally-fix\n")
        # The back-pointer names a path that did not move: unchanged.
        self.assertEqual((self.home / "personal/tally/.git/worktrees/tally-fix/gitdir").read_text(),
                         f"{self.home}/wt/tally-fix/.git\n")

    def fake_proc(self, processes):
        """A /proc tree: pid -> (cwd, parent pid). Every entry is owned by this user, like hermes's own."""
        root = Path(self.enterContext(TemporaryDirectory()))
        for pid, (cwd, parent) in processes.items():
            entry = root / str(pid)
            entry.mkdir()
            (entry / "stat").write_text(f"{pid} (some (odd) name) S {parent} 1 1 0\n")
            (entry / "cmdline").write_bytes(b"cargo\0build\0")
            (entry / "cwd").symlink_to(cwd)
        (root / "self").mkdir()  # not a pid: ignored
        saved, migrate.PROC = migrate.PROC, root
        self.addCleanup(setattr, migrate, "PROC", saved)
        return root

    def test_processes_with_their_cwd_in_a_moved_tree_refuse(self):
        self.old_layout()
        me, parent = os.getpid(), 4100
        self.fake_proc({
            4242: (str(self.home / "work/rust-app-template/src"), 1),       # a build in a personal repo
            4243: (str(self.home / "work-devzero/devzero/nautili"), 1),     # a shell in a company repo
            4244: (str(self.home / "elsewhere"), 1),                        # unrelated
            me: (str(self.home / "work"), parent),                          # this process: ignored
            parent: (str(self.home / "work-devzero"), 1),                   # its parent shell: ignored
        })
        before = snapshot(self.home)
        status, log = self.run_migration()
        self.assertEqual(status, migrate.REFUSED, log)
        self.assertIn("4242 (cargo build) in", log)
        self.assertIn("4243 (cargo build) in", log)
        self.assertNotIn("4244", log)
        self.assertNotIn(f"{me} (", log)
        self.assertNotIn(f"{parent} (", log)
        self.assertEqual(snapshot(self.home), before)
        for pid in (4242, 4243):
            shutil.rmtree(migrate.PROC / str(pid))
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assertTrue((self.home / "personal/rust-app-template").is_dir())

    # --- fix round 2 ------------------------------------------------------------------------

    def test_old_personal_slot_without_work_devzero_refuses_not_stamps(self):
        # R1: the old layout with its evidence missing must not be stamped as the new one.
        for name in ("work/.task-lock", "work/.task-queue", "work/.current-task"):
            with self.subTest(slot=name):
                shutil.rmtree(self.home)
                self.home.mkdir()
                write(self.home / "work/tally/README.md", "tally\n")
                write(self.home / name)
                (self.home / "personal").mkdir()  # tmpfiles
                before = snapshot(self.home)
                status, log = self.run_migration()
                self.assertEqual(status, migrate.REFUSED, log)
                self.assertIn("has the old personal slot", log)
                self.assertIn("create an empty", log)
                self.assertEqual(snapshot(self.home), before)
                self.assertFalse(self.stamped())
        # The recovery the message names: an empty ~/work-devzero, then run again.
        (self.home / "work-devzero").mkdir()
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assertEqual((self.home / "personal/tally/README.md").read_text(), "tally\n")
        self.assertFalse((self.home / "work").exists())
        self.assertFalse((self.home / "work-devzero").exists())
        self.assertTrue(self.stamped())

    def test_no_stamp_while_work_devzero_still_holds_files(self):
        # R4: a file lands in ~/work-devzero during a personal-only move (only with the gateway running).
        write(self.home / "work/tally/README.md", "tally\n")
        write(self.home / "work/.task-lock")
        (self.home / "work-devzero").mkdir()
        real = migrate.processes_in

        def arrive(trees):
            if len(trees) == 3:  # the final check, right before the renames
                write(self.home / "work-devzero/.tasks/devzero/.task-queue", ROW)
            return real(trees)

        migrate.processes_in = arrive
        self.addCleanup(setattr, migrate, "processes_in", real)
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assertTrue((self.home / "personal/tally").is_dir())
        self.assertIn("still holds files; not stamping", log)
        self.assertFalse(self.stamped())
        # Next run: the company half is now pending and runs.
        migrate.processes_in = real
        status, log = self.run_migration()
        self.assertEqual(status, 0, log)
        self.assertEqual((self.home / "work/.tasks/devzero/.task-queue").read_text(), ROW)
        self.assertTrue(self.stamped())

    def test_process_entering_during_the_walk_refuses_before_any_rename(self):
        # R8: re-checked right before the renames, and ~/personal (an empty target skeleton) counts too.
        self.old_layout()
        self.tmpfiles_skeleton()
        proc = self.fake_proc({})
        real = migrate.gitdir_rewrites

        def walk_then_enter(trees, moves):
            found = real(trees, moves)
            entry = proc / "4300"
            entry.mkdir()
            (entry / "stat").write_text("4300 (sh) S 1 1 1 0\n")
            (entry / "cmdline").write_bytes(b"sh\0")
            (entry / "cwd").symlink_to(self.home / "personal")
            return found

        migrate.gitdir_rewrites = walk_then_enter
        self.addCleanup(setattr, migrate, "gitdir_rewrites", real)
        before = snapshot(self.home)
        status, log = self.run_migration()
        self.assertEqual(status, migrate.REFUSED, log)
        self.assertIn(f"4300 (sh) in {self.home}/personal", log)
        self.assertEqual(snapshot(self.home), before)
        self.assertFalse(self.stamped())

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
