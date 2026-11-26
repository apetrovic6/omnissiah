"""The personal coder's task tools in worktree mode (HERMES_TASK_MODE=worktrees), against real Git repos.

Slot mode (the company wrappers) is covered, unchanged, by tests/test_hermes_task.py.
"""

import fcntl
import json
import os
import shutil
import signal
import subprocess
import sys
import time
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory


TOOL = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-task.py"
MATRIX = ("!room:matrix.example:8448", "$request")
OTHER = ("!opaque_room-id", "$event+/_=-")
APP_PROJECTS = ("rust-app-template", "tally")
EMAIL = "hermes@example.org"
SHIM = """#!/bin/sh
case " $* " in
  *" worktree add "*) : > "$SHIM_DIR/started"; while [ ! -e "$SHIM_DIR/release" ]; do sleep 0.05; done ;;
esac
exec git "$@"
"""


def row(timestamp, room, thread, project="tally", branch="pending", summary="Old request"):
    return "\t".join((timestamp, room, thread, project, branch, summary)) + "\n"


def thread(number):
    return (MATRIX[0], f"$t{number}")


def ago(**delta):
    return (datetime.now(UTC) - timedelta(**delta)).isoformat().replace("+00:00", "Z")


def reservation(reserved_at, action="new", start=None, nonce="0123456789abcdef"):
    return {"reserved_at": reserved_at, "nonce": nonce, "action": action, "start": start}


class WorktreeTasks(unittest.TestCase):
    def setUp(self):
        self.home = Path(self.enterContext(TemporaryDirectory()))
        self.personal = self.home / "personal"
        self.personal.mkdir()
        self.git_env = {
            "PATH": os.environ["PATH"], "HOME": str(self.home), "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": EMAIL, "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": EMAIL,
        }
        self.env = {
            **self.git_env,
            "HERMES_TASK_MODE": "worktrees",
            "HERMES_TASK_APP_PROJECTS": json.dumps(APP_PROJECTS),
            "HERMES_TASK_REPO_ROOT": str(self.personal),
            "HERMES_TASK_LOCK_WAIT": "5",
        }
        seed = self.home / "seed"
        seed.mkdir()
        self.git(seed, "init", "-q", "-b", "main")
        (seed / ".gitignore").write_text("target/\n")
        (seed / "README.md").write_text("tally\n")
        self.git(seed, "add", ".gitignore", "README.md")
        self.git(seed, "commit", "-q", "-m", "init")
        self.upstream = self.home / "remotes/upstream.git"
        self.fork = self.home / "remotes/fork.git"
        for bare in (self.upstream, self.fork):
            self.git(self.home, "clone", "-q", "--bare", str(seed), str(bare))
        self.base = self.personal / "tally"
        self.git(self.home, "clone", "-q", "-o", "upstream", str(self.upstream), str(self.base))
        self.git(self.base, "remote", "add", "origin", str(self.fork))
        self.git(self.base, "fetch", "-q", "origin")

    # --- helpers --------------------------------------------------------------------------

    def git(self, cwd, *args, check=True):
        result = subprocess.run(["git", "-C", str(cwd), *args], env=self.git_env, capture_output=True, text=True,
                                check=False)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip() if check else result

    def invoke(self, *args, summary="", code=0, env=None):
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(TOOL), *args], input=summary, text=True, encoding="utf-8",
            capture_output=True, env={**self.env, **(env or {})}, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def task(self, *args, summary="", env=None):
        return json.loads(self.invoke(*args, summary=summary, env=env).stdout)

    def claim(self, origin=MATRIX, project="tally", summary="Matrix task", env=None):
        return self.task("task-claim", "--", *origin, project, "-", summary=summary, env=env)

    def claim_app(self, project="tally", summary="App task"):
        return self.task("task-claim", "--app", "new", "--", project, "-", summary=summary)

    @staticmethod
    def who(claim):
        active = claim["active"]
        if active["origin_kind"] == "app":
            return ("--app", active["session_id"], "--")
        return ("--", active["room"], active["thread"])

    def branch(self, claim, name, *flags, code=0):
        result = self.invoke("task-branch", *flags, *self.who(claim), claim["active"]["started_at"], name, code=code)
        return json.loads(result.stdout) if code == 0 else result

    def done(self, claim, code=0):
        result = self.invoke("task-done", *self.who(claim), claim["active"]["started_at"], code=code)
        return json.loads(result.stdout) if code == 0 else result

    def state(self):
        path = self.personal / ".task-state.json"
        return json.loads(path.read_text()) if path.exists() else None

    def record(self, task_id):
        return next(t for t in self.state()["tasks"] if t["task_id"] == task_id)

    def edit_record(self, task_id, **fields):
        data = self.state()
        next(t for t in data["tasks"] if t["task_id"] == task_id).update(fields)
        (self.personal / ".task-state.json").write_text(json.dumps(data))

    def worktrees(self):
        return [line.removeprefix("worktree ") for line in self.git(self.base, "worktree", "list", "--porcelain")
                .splitlines() if line.startswith("worktree ")]

    def trash(self):
        trash = self.personal / ".worktrees/.trash"
        return sorted(trash.iterdir()) if trash.exists() else []

    # --- claims and isolation -------------------------------------------------------------

    def test_claims_run_in_parallel_and_an_origin_resumes_its_own(self):
        claims = [self.claim(MATRIX), self.claim(OTHER), self.claim_app()]
        self.assertEqual([c["result"] for c in claims], ["claimed"] * 3)
        ids = [c["active"]["task_id"] for c in claims]
        self.assertEqual(len(set(ids)), 3)
        for claim in claims:
            self.assertRegex(claim["active"]["task_id"], r"\A[0-9a-f]{16}\Z")
            # The path is handed out only once task-branch has created it.
            self.assertNotIn("worktree_path", claim)
            self.assertEqual((claim["active"]["branch"], claim["active"]["worktree"], claim["owned"]),
                             ("pending", None, True))
        app = claims[2]
        self.assertNotEqual(app["session_id"], app["active"]["task_id"])
        again = self.claim(MATRIX, project="rust-app-template", summary="Don't replace")
        self.assertEqual((again["result"], again["active"]["task_id"], again["active"]["summary"]),
                         ("active", ids[0], "Matrix task"))
        self.assertEqual(len(self.state()["tasks"]), 3)
        self.assertEqual(self.task("task-status"), {"result": "active", "live": 3, "max_live": None})

    def test_two_tasks_on_one_repo_get_their_own_worktrees_and_branches(self):
        a, b = self.claim(thread(1)), self.claim(thread(2))
        made = self.branch(a, "hermes/a")
        wt_a = Path(made["active"]["worktree"])
        self.assertEqual((made["result"], made["active"]["branch"]), ("updated", "hermes/a"))
        self.assertEqual(self.git(wt_a, "symbolic-ref", "HEAD"), "refs/heads/hermes/a")
        self.assertEqual(self.git(wt_a, "rev-parse", "HEAD"), self.git(self.base, "rev-parse", "upstream/main"))
        # New branches don't track the upstream default branch (a bare push would go there).
        self.assertNotEqual(self.git(wt_a, "rev-parse", "--abbrev-ref", "@{u}", check=False).returncode, 0)
        before = self.state()
        refused = self.branch(b, "hermes/a", code=2)
        self.assertIn("belongs to another live task", refused.stderr)
        self.assertEqual(self.state(), before)
        wt_b = Path(self.branch(b, "hermes/b")["active"]["worktree"])
        self.assertNotEqual(wt_a, wt_b)
        self.assertEqual(sorted(self.worktrees()), sorted(map(str, (self.base, wt_a, wt_b))))
        # Same branch again is a no-op; another branch needs a new task.
        self.assertEqual(self.branch(a, "hermes/a")["active"]["worktree"], str(wt_a))
        self.assertIn("finish it with task-done", self.branch(a, "hermes/c", code=2).stderr)
        for name in ("pending", "-x", "bad..name", "a b"):
            with self.subTest(name=name):
                self.assertIn("Invalid branch name", self.branch(b, name, code=2).stderr)

    def test_commands_act_only_on_their_own_task(self):
        a, b = self.claim(thread(1)), self.claim(thread(2))
        self.branch(a, "hermes/a")
        made_b = self.branch(b, "hermes/b")
        (Path(made_b["active"]["worktree"]) / "b.txt").write_text("b's work\n")
        record_b = self.record(b["active"]["task_id"])
        wrong = ("--", *thread(1), b["active"]["started_at"])
        before = self.state()
        self.assertIn("No live task", self.invoke("task-done", *wrong, code=2).stderr)
        self.invoke("task-branch", *wrong, "hermes/x", code=2)
        self.assertEqual(self.state(), before)
        self.assertEqual(self.done(a)["result"], "done")
        self.assertEqual(self.state()["tasks"], [record_b])
        self.assertEqual((Path(made_b["active"]["worktree"]) / "b.txt").read_text(), "b's work\n")
        self.assertEqual(self.task("task-status", "--", *thread(1))["result"], "none")
        status_b = self.task("task-status", "--", *thread(2))
        self.assertTrue(status_b["owned"])
        self.assertEqual(status_b["active"]["task_id"], b["active"]["task_id"])

    # --- done, follow-ups ---------------------------------------------------------------

    def test_done_removes_a_clean_worktree_and_keeps_the_branch(self):
        a = self.claim()
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        (wt / "new.txt").write_text("untracked\n")
        before = self.state()
        self.assertIn("1 uncommitted change", self.done(a, code=2).stderr)
        (wt / "new.txt").unlink()
        (wt / "README.md").write_text("edited\n")
        self.assertIn("uncommitted", self.done(a, code=2).stderr)
        self.assertEqual(self.state(), before)
        self.git(wt, "add", "README.md")
        self.git(wt, "commit", "-q", "-m", "work")
        tip = self.git(wt, "rev-parse", "HEAD")
        (wt / "target").mkdir()
        (wt / "target/out").write_text("ignored build output\n")
        done = self.done(a)
        self.assertEqual((done["result"], done["branch"], done["worktree_removed"], done["owned"]),
                         ("done", "hermes/a", True, False))
        self.assertFalse(wt.exists())
        self.assertEqual(self.worktrees(), [str(self.base)])
        self.assertEqual(self.git(self.base, "rev-parse", "refs/heads/hermes/a"), tip)
        self.assertEqual(self.trash(), [])
        self.assertIsNone(self.state())

    def test_follow_up_fast_forwards_the_pr_branch_and_refuses_otherwise(self):
        first = self.claim(thread(1))
        wt = Path(self.branch(first, "hermes/pr")["active"]["worktree"])
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "pr work")
        self.git(wt, "push", "-q", "-u", "origin", "hermes/pr")
        # The local branch equals origin's: done deletes it, so a later rewrite of the PR can't wedge a follow-up.
        self.assertTrue(self.done(first)["branch_deleted"])
        self.assertNotEqual(self.git(self.base, "show-ref", "--verify", "refs/heads/hermes/pr", check=False).returncode, 0)

        second = self.claim(thread(2))
        self.assertIn("already exists on origin", self.branch(second, "hermes/pr", code=2).stderr)
        wt = Path(self.branch(second, "hermes/pr", "--follow-up")["active"]["worktree"])
        self.assertEqual(self.git(wt, "rev-parse", "--abbrev-ref", "@{u}"), "origin/hermes/pr")
        self.done(second)

        # A reviewer's fix lands on the fork: the next follow-up fast-forwards to it.
        other = self.home / "other"
        self.git(self.home, "clone", "-q", "-b", "hermes/pr", str(self.fork), str(other))
        self.git(other, "commit", "-q", "--allow-empty", "-m", "remote fix")
        self.git(other, "push", "-q", "origin", "hermes/pr")
        self.git(self.base, "fetch", "-q", "origin")
        third = self.claim(thread(3))
        wt = Path(self.branch(third, "hermes/pr", "--follow-up")["active"]["worktree"])
        self.assertEqual(self.git(wt, "rev-parse", "HEAD"), self.git(other, "rev-parse", "HEAD"))
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "unpushed")
        self.assertFalse(self.done(third)["branch_deleted"])  # ahead of origin: kept

        fourth = self.claim(thread(4))
        self.assertIn("aren't on origin/hermes/pr", self.branch(fourth, "hermes/pr", "--follow-up", code=2).stderr)
        self.assertIn("No origin/hermes/none", self.branch(fourth, "hermes/none", "--follow-up", code=2).stderr)
        self.assertEqual(self.record(fourth["active"]["task_id"])["branch"], "pending")
        # The app form takes the flag before its origin, too.
        app = self.claim_app()
        self.branch(app, "hermes/new")

    # --- cap, stale, clear --------------------------------------------------------------

    def test_cap_refuses_new_claims_without_a_queue(self):
        cap = {"HERMES_TASK_MAX_LIVE": "2"}
        first = self.claim(thread(1), env=cap)
        self.claim(thread(2), env=cap)
        before = self.state()
        busy = self.claim(thread(3), env=cap)
        self.assertEqual({key: busy[key] for key in ("result", "active", "owned", "live", "max_live")},
                         {"result": "busy", "active": None, "owned": False, "live": 2, "max_live": 2})
        self.assertEqual(self.state(), before)
        self.assertEqual(self.claim(thread(1), env=cap)["result"], "active")  # resuming is never capped
        self.done(first)
        self.assertEqual(self.claim(thread(3), env=cap)["result"], "claimed")

    def test_bad_config_exits_before_any_write(self):
        for env in ({"HERMES_TASK_MAX_LIVE": "0"}, {"HERMES_TASK_MAX_LIVE": "x"}, {"HERMES_TASK_MAX_LIVE": "+3"},
                    {"HERMES_TASK_STALE_HOURS": "0"}, {"HERMES_TASK_REPO_ROOT": "personal"},
                    {"HERMES_TASK_BASE_REMOTE": "-x"}, {"HERMES_TASK_MODE": "slots"}):
            with self.subTest(env=env):
                self.invoke("task-claim", "--", *MATRIX, "tally", "-", summary="x", env=env, code=2)
                self.assertEqual(sorted(p.name for p in self.personal.iterdir()), ["tally"])

    def test_stale_tasks_are_listed_and_clear_saves_uncommitted_work(self):
        a, b = self.claim(thread(1), summary="Stale one"), self.claim(thread(2))
        task_id = a["active"]["task_id"]
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        self.edit_record(task_id, last_active="2024-01-01T00:00:00Z")
        listed = {t["task_id"]: t for t in self.task("task-status", "--all")["tasks"]}
        self.assertTrue(listed[task_id]["possibly_stale"])
        self.assertFalse(listed[b["active"]["task_id"]]["possibly_stale"])
        self.assertGreater(listed[task_id]["idle_seconds"], 86400)
        self.assertTrue(listed[task_id]["worktree_exists"])
        (wt / "new.txt").write_text("untracked work\n")
        (wt / "README.md").write_text("edited\n")
        (wt / "target").mkdir()
        (wt / "target/out").write_text("ignored\n")
        self.invoke("task-clear", code=2)
        self.invoke("task-clear", "--", *thread(9), code=2)
        cleared = self.task("task-clear", "--id", task_id)
        self.assertEqual((cleared["result"], cleared["wip_ref"], cleared["worktree_removed"]),
                         ("cleared", f"refs/hermes/wip/{task_id}", True))
        self.assertFalse(wt.exists())
        self.assertEqual(self.git(self.base, "show", f"{cleared['wip_ref']}:new.txt"), "untracked work")
        self.assertEqual(self.git(self.base, "show", f"{cleared['wip_ref']}:README.md"), "edited")
        self.assertNotEqual(self.git(self.base, "cat-file", "-e", f"{cleared['wip_ref']}:target/out",
                                     check=False).returncode, 0)
        self.assertEqual(self.git(self.base, "rev-parse", "hermes/a"), self.git(self.base, "rev-parse", "upstream/main"))
        # clear from the task's own conversation; a clean worktree needs no wip ref.
        self.branch(b, "hermes/b")
        cleared = self.task("task-clear", "--", *thread(2))
        self.assertEqual((cleared["wip_ref"], cleared["worktree_removed"]), (None, True))
        self.assertIsNone(self.state())

    def test_orphaned_worktrees_are_listed_and_clearable(self):
        orphan = self.personal / ".worktrees/tally/deadbeefdeadbeef"
        orphan.mkdir(parents=True)
        (orphan / "file").write_text("left over\n")
        self.assertEqual(self.task("task-status", "--all")["orphans"], ["tally/deadbeefdeadbeef"])
        self.invoke("task-clear", "--id", "tally/../x", code=2)
        self.invoke("task-clear", "--id", "tally/nothing", code=2)
        cleared = self.task("task-clear", "--id", "tally/deadbeefdeadbeef")
        # Not a Git worktree: kept aside, never deleted.
        self.assertEqual((cleared["worktree_removed"], cleared["wip_ref"]), (False, None))
        self.assertEqual((Path(cleared["kept"]) / "file").read_text(), "left over\n")
        self.assertEqual(self.task("task-status", "--all")["orphans"], [])

    def test_listing_never_shows_origin_ids(self):
        matrix, app = self.claim(MATRIX, summary="Matrix summary"), self.claim_app(summary="App summary")
        listing = self.task("task-status", "--all")
        text = json.dumps(listing)
        for secret in (*MATRIX, app["session_id"]):
            self.assertNotIn(json.dumps(secret)[1:-1], text)
        self.assertEqual({t["task_id"] for t in listing["tasks"]},
                         {matrix["active"]["task_id"], app["active"]["task_id"]})
        self.assertEqual({t["summary"] for t in listing["tasks"]}, {"Matrix summary", "App summary"})
        self.invoke("task-status", "--all", "--", *MATRIX, code=2)

    # --- Git edge cases -----------------------------------------------------------------

    def test_worktree_deleted_by_hand_and_stale_registrations_are_pruned(self):
        a = self.claim(thread(1))
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        shutil.rmtree(wt)
        self.assertFalse(self.task("task-status", "--all")["tasks"][0]["worktree_exists"])
        self.assertEqual(self.done(a)["worktree_removed"], False)
        self.assertEqual(self.worktrees(), [str(self.base)])
        # A worktree made by hand and deleted without `git worktree remove`.
        outside = self.home / "outside"
        self.git(self.base, "worktree", "add", "-q", "-b", "hermes/stale", str(outside), "upstream/main")
        self.git(self.base, "push", "-q", "origin", "hermes/stale")
        shutil.rmtree(outside)
        b = self.claim(thread(2))
        self.assertEqual(self.branch(b, "hermes/stale", "--follow-up")["result"], "updated")

    def test_locked_worktrees_are_never_removed(self):
        a = self.claim()
        wt = self.branch(a, "hermes/a")["active"]["worktree"]
        self.git(self.base, "worktree", "lock", wt)
        self.assertIn("locked worktree", self.done(a, code=2).stderr)
        self.assertIn("locked worktree", self.invoke("task-clear", "--id", a["active"]["task_id"], code=2).stderr)
        self.assertTrue(Path(wt).is_dir())
        self.git(self.base, "worktree", "unlock", wt)
        self.assertEqual(self.done(a)["result"], "done")

    def test_branch_checked_out_elsewhere(self):
        self.git(self.base, "branch", "hermes/base", "upstream/main")
        self.git(self.base, "push", "-q", "origin", "hermes/base")
        self.git(self.base, "checkout", "-q", "hermes/base")
        (self.base / "scratch.txt").write_text("manjo's\n")
        a = self.claim(thread(1))
        self.assertIn("uncommitted changes", self.branch(a, "hermes/base", "--follow-up", code=2).stderr)
        (self.base / "scratch.txt").unlink()
        self.assertEqual(self.branch(a, "hermes/base", "--follow-up")["result"], "updated")
        self.assertNotEqual(self.git(self.base, "symbolic-ref", "-q", "HEAD", check=False).returncode, 0)
        # In another (non-task) worktree: refused, naming it.
        other = self.home / "other-wt"
        self.git(self.base, "worktree", "add", "-q", "-b", "hermes/o", str(other), "upstream/main")
        self.git(self.base, "push", "-q", "origin", "hermes/o")
        b = self.claim(thread(2))
        self.assertIn(f"checked out in {other}", self.branch(b, "hermes/o", "--follow-up", code=2).stderr)

    def test_unknown_default_branch_or_missing_base_clone(self):
        a = self.claim()
        self.git(self.base, "remote", "set-head", "upstream", "--delete")
        self.assertIn("set-head upstream --auto", self.branch(a, "hermes/a", code=2).stderr)
        self.assertEqual(self.record(a["active"]["task_id"])["branch"], "pending")
        app = self.claim_app(project="rust-app-template")
        self.assertIn("No base clone", self.branch(app, "hermes/a", code=2).stderr)

    # --- lock and crash recovery ----------------------------------------------------------

    def test_held_lock_exits_75(self):
        with open(self.personal / ".task-lock", "ab") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.invoke("task-status", env={"HERMES_TASK_LOCK_WAIT": "0.2"}, code=75)

    def test_lock_is_released_while_git_checks_out(self):
        shim = self.home / "git-shim"
        shim.write_text(SHIM)
        shim.chmod(0o755)
        a, b = self.claim(thread(1)), self.claim(thread(2))
        env = {**self.env, "HERMES_TASK_GIT": str(shim), "SHIM_DIR": str(self.home)}
        slow = subprocess.Popen(
            [sys.executable, "-I", "-B", str(TOOL), "task-branch", *self.who(a), a["active"]["started_at"], "hermes/slow"],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            deadline = time.monotonic() + 20
            while not (self.home / "started").exists():
                self.assertIsNone(slow.poll(), slow.stderr.read() if slow.poll() is not None else "")
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.05)
            # The checkout is running: other tasks' commands still get the lock.
            quick = {"HERMES_TASK_LOCK_WAIT": "1"}
            self.assertTrue(self.task("task-status", "--", *thread(2), env=quick)["owned"])
            reserved = self.invoke("task-branch", *self.who(b), b["active"]["started_at"], "hermes/slow", env=quick,
                                   code=2)
            self.assertIn("belongs to another live task", reserved.stderr)
            self.assertIn("still being created", self.done(a, code=2).stderr)
        finally:
            (self.home / "release").write_text("")
            out, err = slow.communicate(timeout=30)
        self.assertEqual(slow.returncode, 0, err)
        self.assertEqual(json.loads(out)["active"]["branch"], "hermes/slow")
        self.assertFalse(self.record(a["active"]["task_id"])["preparing"])

    def test_an_interrupted_task_branch_is_finished_by_the_next_one(self):
        a, b = self.claim(thread(1)), self.claim(thread(2))
        path_a = self.personal / ".worktrees/tally" / a["active"]["task_id"]
        self.git(self.base, "worktree", "add", "-q", "--no-track", "-b", "hermes/r", str(path_a), "upstream/main")
        self.edit_record(a["active"]["task_id"], branch="hermes/r", worktree=str(path_a), preparing=True,
                         reservation=reservation(ago(minutes=1)))
        self.assertIn("still being created", self.branch(a, "hermes/r", code=2).stderr)  # maybe still running
        # The grace runs from the reservation, not from last_active (which every task-status refreshes).
        self.edit_record(a["active"]["task_id"], reservation=reservation(ago(hours=3)))
        self.assertTrue(self.task("task-status", "--", *thread(1))["owned"])
        self.assertEqual(self.branch(a, "hermes/r")["active"]["worktree"], str(path_a))
        self.assertFalse(self.record(a["active"]["task_id"])["preparing"])
        # A partial directory (git died mid-checkout) is moved away and the worktree made afresh.
        path_b = self.personal / ".worktrees/tally" / b["active"]["task_id"]
        path_b.mkdir(parents=True)
        (path_b / "junk").write_text("partial\n")
        self.edit_record(b["active"]["task_id"], branch="hermes/p", worktree=str(path_b), preparing=True,
                         reservation=reservation(ago(hours=3)))
        self.assertIn("still setting up", self.branch(b, "hermes/other", code=2).stderr)
        self.branch(b, "hermes/p")
        self.assertFalse((path_b / "junk").exists())
        kept = list((self.personal / ".worktrees/.kept").iterdir())
        self.assertEqual([(k / "junk").read_text() for k in kept], ["partial\n"])  # kept aside, never deleted
        self.assertEqual(self.git(path_b, "symbolic-ref", "HEAD"), "refs/heads/hermes/p")
        self.assertEqual(self.trash(), [])

    # --- state validity and the old slot --------------------------------------------------

    def test_invalid_state_refuses_until_manjo_repairs_it(self):
        self.claim()
        data = self.state()
        tampered = dict(data["tasks"][0], worktree=str(self.home / "elsewhere"), branch="hermes/x")
        for bad in ("{", json.dumps({"version": 2, "tasks": []}), json.dumps({"version": True, "tasks": []}),
                    json.dumps({"version": 1, "tasks": [tampered]})):
            with self.subTest(bad=bad[:40]):
                (self.personal / ".task-state.json").write_text(bad)
                stderr = self.invoke("task-status", code=2).stderr
                self.assertIn("ask manjo for 'clear task'", stderr)
                self.assertIn("task-clear --repair", stderr)
                self.invoke("task-claim", "--", *OTHER, "tally", "-", summary="x", code=2)
        repaired = self.task("task-clear", "--repair")
        self.assertEqual(repaired["result"], "repaired")
        self.assertRegex(repaired["moved"][0], r"\A\.task-state\.json\.bad-")
        self.assertEqual(self.task("task-status")["live"], 0)
        self.assertEqual(self.task("task-clear", "--repair")["result"], "ok")
        self.invoke("task-clear", "--repair", "--", *MATRIX, code=2)

    def test_old_slot_and_queue_become_live_tasks_once(self):
        app_id = "0123456789abcdef"
        (self.personal / ".current-task").write_text(
            row("2026-11-20T10:00:00Z", *MATRIX, branch="hermes/old", summary="Old active"))
        (self.personal / ".task-queue").write_text(
            row("2026-11-20T10:00:00.000001Z", *MATRIX, summary="Interrupted promotion duplicate")
            + row("2026-11-20T11:00:00Z", *OTHER, summary="Queued Matrix")
            + row("2026-11-20T12:00:00Z", f"app:{app_id}", "", "rust-app-template", summary="Queued app"))
        first = self.invoke("task-status", "--all")
        self.assertIn("Moved the old task slot", first.stderr)
        listing = json.loads(first.stdout)
        self.assertEqual(len(listing["tasks"]), 3)
        names = sorted(p.name for p in self.personal.iterdir())
        self.assertFalse({".current-task", ".task-queue"} & set(names))
        self.assertEqual(len([n for n in names if ".migrated-" in n]), 2)
        legacy = self.task("task-status", "--", *MATRIX)
        self.assertTrue(legacy["owned"])
        self.assertEqual({k: legacy["active"][k] for k in ("started_at", "branch", "worktree", "legacy", "summary")},
                         {"started_at": "2026-11-20T10:00:00Z", "branch": "hermes/old", "worktree": str(self.base),
                          "legacy": True, "summary": "Old active"})
        queued = self.task("task-status", "--", *OTHER)
        self.assertEqual((queued["active"]["started_at"], queued["active"]["branch"], queued["active"]["legacy"]),
                         ("2026-11-20T11:00:00Z", "pending", False))
        self.assertTrue(self.task("task-status", "--app", app_id, "--")["owned"])
        self.assertEqual(len(self.task("task-status", "--all")["tasks"]), 3)
        legacy_claim = {"active": legacy["active"]}
        self.assertIn("predates worktrees", self.branch(legacy_claim, "hermes/new", code=2).stderr)
        self.assertEqual(self.done(legacy_claim)["worktree_removed"], False)
        self.assertTrue((self.base / ".git").is_dir())
        # The queued task now starts normally.
        self.assertEqual(self.branch({"active": queued["active"]}, "hermes/q")["result"], "updated")

    def test_invalid_old_slot_refuses_until_repaired(self):
        (self.personal / ".current-task").write_text("garbage\n")
        stderr = self.invoke("task-status", code=2).stderr
        self.assertIn("Invalid old task slot state", stderr)
        self.assertIn("task-clear --repair", stderr)
        self.assertTrue((self.personal / ".current-task").exists())
        repaired = self.task("task-clear", "--repair")
        self.assertEqual(repaired["result"], "repaired")
        self.assertRegex(repaired["moved"][0], r"\A\.current-task\.bad-")
        self.assertEqual(self.task("task-status")["result"], "idle")


    # --- never discard work Git can't account for (review round 1) ------------------------

    def run_tool(self, *args, env=None):
        return subprocess.run([sys.executable, "-I", "-B", str(TOOL), *args], env={**self.env, **(env or {})},
                              capture_output=True, text=True, timeout=60, check=False)

    def kept(self):
        kept = self.personal / ".worktrees/.kept"
        return sorted(kept.iterdir()) if kept.exists() else []

    def filtered_file(self, smudge, required=False):
        """An upstream file whose checkout runs `smudge` (a filter configured in the base clone only)."""
        seed = self.home / "filterseed"
        self.git(self.home, "clone", "-q", str(self.upstream), str(seed))
        (seed / ".gitattributes").write_text("big.bin filter=slow\n")
        (seed / "big.bin").write_text("payload\n")
        self.git(seed, "add", ".gitattributes", "big.bin")
        self.git(seed, "commit", "-q", "-m", "filtered file")
        self.git(seed, "push", "-q", "origin", "main")
        self.git(self.base, "fetch", "-q", "upstream")
        self.git(self.base, "config", "filter.slow.smudge", smudge)
        self.git(self.base, "config", "filter.slow.clean", "cat")
        if required:
            self.git(self.base, "config", "filter.slow.required", "true")

    def slow_filter(self):
        script = self.home / "smudge.sh"
        script.write_text('#!/bin/sh\n: > "$SHIM_DIR/started"\n'
                          'while [ ! -e "$SHIM_DIR/release" ]; do sleep 0.05; done\ncat\n')
        script.chmod(0o755)
        self.filtered_file(str(script))

    def start_branch(self, claim, name, *flags, env=None):
        proc = subprocess.Popen(
            [sys.executable, "-I", "-B", str(TOOL), "task-branch", *flags, *self.who(claim),
             claim["active"]["started_at"], name],
            env={**self.env, "SHIM_DIR": str(self.home), **(env or {})}, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        deadline = time.monotonic() + 20
        while not (self.home / "started").exists():
            if proc.poll() is not None:
                self.fail(proc.stderr.read())
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.05)
        return proc

    def age_reservation(self, task_id, **delta):
        record = self.record(task_id)
        self.edit_record(task_id, reservation={**record["reservation"], "reserved_at": ago(**delta)})

    def add_submodule(self, wt):
        seed = self.home / "subseed"
        seed.mkdir()
        self.git(seed, "init", "-q", "-b", "main")
        (seed / "lib.txt").write_text("lib\n")
        self.git(seed, "add", "lib.txt")
        self.git(seed, "commit", "-q", "-m", "lib")
        self.git(wt, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(seed), "sub")
        self.git(wt, "commit", "-q", "-m", "add sub")

    def test_submodules_block_done_and_clear_keeps_them_aside(self):
        a = self.claim()
        task_id = a["active"]["task_id"]
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        self.add_submodule(wt)
        (wt / "sub/lib.txt").write_text("changed in the task\n")
        self.git(wt / "sub", "commit", "-q", "-a", "-m", "unpushed submodule commit")
        sub_commit = self.git(wt / "sub", "rev-parse", "HEAD")
        self.git(wt, "add", "sub")
        self.git(wt, "commit", "-q", "-m", "bump sub")
        self.assertEqual(self.git(wt, "status", "--porcelain"), "")
        self.assertIn("has submodules; ask manjo", self.done(a, code=2).stderr)
        self.assertTrue(wt.is_dir())
        cleared = self.task("task-clear", "--id", task_id)
        self.assertEqual((cleared["worktree_removed"], cleared["wip_ref"]), (False, None))
        self.assertTrue((Path(cleared["kept"]) / "sub/lib.txt").is_file())
        # The submodule's objects live in the worktree's admin dir; a kept worktree keeps it (locked).
        admin = self.base / ".git/worktrees" / task_id
        # (Its core.worktree still names the old place, hence --work-tree: the objects are what matters.)
        self.assertEqual(self.git(self.home, "--git-dir", str(admin / "modules/sub"), "--work-tree", str(self.home),
                                  "cat-file", "-t", sub_commit), "commit")
        self.git(self.base, "worktree", "prune")
        self.assertTrue(admin.is_dir())

    def test_done_refuses_work_only_the_worktree_holds_and_clear_saves_it(self):
        a = self.claim(thread(1))
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        self.git(wt, "checkout", "-q", "--detach")
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "detached work")
        lost = self.git(wt, "rev-parse", "HEAD")
        self.assertIn("not on a branch", self.done(a, code=2).stderr)
        cleared = self.task("task-clear", "--id", a["active"]["task_id"])  # a clean tree, but unreachable work
        self.assertIsNotNone(cleared["wip_ref"])
        self.assertEqual(self.git(self.base, "merge-base", "--is-ancestor", lost, cleared["wip_ref"],
                                  check=False).returncode, 0)

        b = self.claim(thread(2))
        wt = Path(self.branch(b, "hermes/b")["active"]["worktree"])
        (wt / "file.txt").write_text("one\n")
        self.git(wt, "add", "file.txt")
        self.git(wt, "commit", "-q", "-m", "one")
        rebase = subprocess.run(["git", "-C", str(wt), "rebase", "-q", "-i", "HEAD~1"], capture_output=True, text=True,
                                env={**self.git_env, "GIT_SEQUENCE_EDITOR": "sed -i 1s/^pick/edit/"}, check=False)
        self.assertEqual(rebase.returncode, 0, rebase.stderr)
        self.git(wt, "commit", "-q", "--amend", "-m", "amended mid-rebase")
        self.assertEqual(self.git(wt, "status", "--porcelain"), "")
        self.assertIn("in progress", self.done(b, code=2).stderr)
        self.git(wt, "rebase", "--abort")
        self.assertEqual(self.done(b)["result"], "done")

    def test_commits_only_the_head_reflog_holds_are_saved_on_done(self):
        a = self.claim(thread(1))
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        self.git(wt, "checkout", "-q", "--detach")
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "detached work")
        detached = self.git(wt, "rev-parse", "HEAD")
        refused = self.done(a, code=2).stderr
        self.assertIn("git switch -c 'hermes/a-wip'", refused)
        self.assertIn("don't just check the branch out", refused)
        # The agent checks the branch out anyway, and amends a commit on it: both old tips are saved.
        self.git(wt, "checkout", "-q", "hermes/a")
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "first try")
        first_try = self.git(wt, "rev-parse", "HEAD")
        self.git(wt, "commit", "-q", "--amend", "--allow-empty", "-m", "second try")
        done = self.done(a)
        self.assertEqual(done["worktree_removed"], True)
        ref = done["wip_ref"]
        self.assertEqual(ref, f"refs/hermes/wip/{a['active']['task_id']}")
        for lost in (detached, first_try):
            self.assertEqual(self.git(self.base, "merge-base", "--is-ancestor", lost, ref, check=False).returncode, 0)
        # Nothing to save: no wip ref.
        b = self.claim(thread(2))
        self.branch(b, "hermes/b")
        self.assertIsNone(self.done(b)["wip_ref"])

    def test_done_keeps_the_branch_unless_the_remote_confirms_it(self):
        a = self.claim(thread(1))
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "pr")
        self.git(wt, "push", "-q", "-u", "origin", "hermes/a")
        # The PR was closed with its branch on the forge; stygies hasn't fetched since.
        self.git(self.fork, "branch", "-q", "-D", "hermes/a")
        self.assertFalse(self.done(a)["branch_deleted"])
        self.assertEqual(self.git(self.base, "rev-parse", "hermes/a"), self.git(self.base, "rev-parse", "origin/hermes/a"))
        # The remote can't be reached: keep it too.
        b = self.claim(thread(2))
        wt = Path(self.branch(b, "hermes/b")["active"]["worktree"])
        self.git(wt, "push", "-q", "-u", "origin", "hermes/b")
        self.git(self.base, "remote", "set-url", "origin", str(self.home / "gone.git"))
        self.assertFalse(self.done(b)["branch_deleted"])
        self.assertTrue(self.git(self.base, "branch", "--list", "hermes/b"))

    def test_uninitialised_submodules_dont_block_done(self):
        sub = self.home / "subseed"
        sub.mkdir()
        self.git(sub, "init", "-q", "-b", "main")
        self.git(sub, "commit", "-q", "--allow-empty", "-m", "lib")
        seed = self.home / "with-sub"
        self.git(self.home, "clone", "-q", str(self.upstream), str(seed))
        self.git(seed, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(sub), "sub")
        self.git(seed, "commit", "-q", "-m", "add a submodule")
        self.git(seed, "push", "-q", "origin", "main")
        self.git(self.base, "fetch", "-q", "upstream")
        a = self.claim()
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        self.assertTrue(self.git(wt, "submodule", "status").startswith("-"))  # never initialised
        self.assertEqual(self.done(a)["worktree_removed"], True)

    def test_a_directory_at_the_worktree_path_is_kept(self):
        a = self.claim()
        path = self.personal / ".worktrees/tally" / a["active"]["task_id"]
        path.mkdir(parents=True)
        (path / "notes.md").write_text("mine\n")
        self.assertEqual(self.branch(a, "hermes/a")["result"], "updated")
        self.assertEqual([(k / "notes.md").read_text() for k in self.kept()], ["mine\n"])

    def test_a_worktree_replaced_by_a_clone_is_kept_on_done(self):
        a = self.claim()
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        shutil.rmtree(wt)
        self.git(self.home, "clone", "-q", str(self.upstream), str(wt))
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "only in the clone")
        commit = self.git(wt, "rev-parse", "HEAD")
        done = self.done(a)
        self.assertEqual(done["worktree_removed"], False)
        self.assertEqual(self.git(Path(done["kept"]), "cat-file", "-t", commit), "commit")

    def test_hidden_edits_and_nested_repos_are_kept(self):
        a = self.claim(thread(1))
        wt = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        self.git(wt, "update-index", "--skip-worktree", "README.md")
        (wt / "README.md").write_text("edited under skip-worktree\n")
        done = self.done(a)
        self.assertEqual(done["worktree_removed"], False)
        self.assertEqual((Path(done["kept"]) / "README.md").read_text(), "edited under skip-worktree\n")

        b = self.claim(thread(2))
        wt = Path(self.branch(b, "hermes/b")["active"]["worktree"])
        nested = wt / "vendor/thing"
        nested.mkdir(parents=True)
        self.git(nested, "init", "-q", "-b", "main")
        self.git(nested, "commit", "-q", "--allow-empty", "-m", "nested work")
        commit = self.git(nested, "rev-parse", "HEAD")
        self.done(b, code=2)
        cleared = self.task("task-clear", "--id", b["active"]["task_id"])
        self.assertEqual((cleared["worktree_removed"], cleared["wip_ref"]), (False, None))
        self.assertEqual(self.git(Path(cleared["kept"]) / "vendor/thing", "cat-file", "-t", commit), "commit")

    def test_an_interrupted_checkout_recovers_and_leaves_no_branch_behind(self):
        self.slow_filter()
        a = self.claim()
        task_id = a["active"]["task_id"]
        proc = self.start_branch(a, "hermes/t")
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait()
        (self.home / "release").write_text("")
        self.assertTrue(self.record(task_id)["preparing"])
        self.assertIn("still being created", self.branch(a, "hermes/t", code=2).stderr)
        self.age_reservation(task_id, minutes=11)
        made = self.branch(a, "hermes/t")
        self.assertEqual(self.git(Path(made["active"]["worktree"]), "symbolic-ref", "HEAD"), "refs/heads/hermes/t")

    def test_a_failed_checkout_deletes_the_branch_it_created(self):
        self.filtered_file("false", required=True)
        a = self.claim()
        self.assertIn("worktree add failed", self.branch(a, "hermes/f", code=2).stderr)
        self.assertEqual(self.record(a["active"]["task_id"])["branch"], "pending")
        self.assertEqual(self.git(self.base, "branch", "--list", "hermes/f"), "")
        self.git(self.base, "config", "filter.slow.smudge", "cat")
        self.assertEqual(self.branch(a, "hermes/f")["result"], "updated")

    def test_a_failing_post_checkout_hook_keeps_the_worktree_with_a_warning(self):
        hook = self.base / ".git/hooks/post-checkout"
        hook.write_text("#!/bin/sh\necho 'git-lfs was not found on your path' >&2\nexit 2\n")
        hook.chmod(0o755)
        a = self.claim()
        made = self.branch(a, "hermes/h")
        self.assertIn("git-lfs was not found", " ".join(made["warnings"]))
        self.assertEqual(self.git(Path(made["active"]["worktree"]), "symbolic-ref", "HEAD"), "refs/heads/hermes/h")

    def test_a_killed_checkout_is_recovered_after_an_hour(self):
        self.slow_filter()
        a = self.claim()
        task_id = a["active"]["task_id"]
        proc = self.start_branch(a, "hermes/k")
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        (self.home / "release").write_text("")
        self.assertIn("locked initializing", self.git(self.base, "worktree", "list", "--porcelain"))
        self.age_reservation(task_id, minutes=30)
        self.assertIn("locked worktree", self.branch(a, "hermes/k", code=2).stderr)
        self.age_reservation(task_id, hours=2)
        made = self.branch(a, "hermes/k")
        self.assertEqual(self.git(Path(made["active"]["worktree"]), "symbolic-ref", "HEAD"), "refs/heads/hermes/k")
        self.assertEqual(len(self.kept()), 1)

    def test_a_slow_task_branch_never_removes_a_worktree_another_one_finished(self):
        shim = self.home / "git-shim"
        shim.write_text('#!/bin/sh\ncase " $* " in *" merge "*) : > "$SHIM_DIR/started"; '
                        'while [ ! -e "$SHIM_DIR/release" ]; do sleep 0.05; done ;; esac\nexec git "$@"\n')
        shim.chmod(0o755)
        first = self.claim(thread(1))
        wt = Path(self.branch(first, "hermes/pr")["active"]["worktree"])
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "pr")
        self.git(wt, "push", "-q", "-u", "origin", "hermes/pr")
        self.git(wt, "commit", "-q", "--allow-empty", "-m", "local only")  # the local branch stays (ahead)
        self.done(first)
        self.git(self.base, "push", "-q", "origin", "hermes/pr")
        a = self.claim(thread(2))
        p1 = self.start_branch(a, "hermes/pr", "--follow-up", env={"HERMES_TASK_GIT": str(shim)})
        self.age_reservation(a["active"]["task_id"], minutes=11)
        p2 = self.branch(a, "hermes/pr", "--follow-up")
        path = Path(p2["active"]["worktree"])
        (path / "agent-started.txt").write_text("work began after p2\n")
        (self.home / "release").write_text("")
        p1.communicate(timeout=30)
        self.assertEqual((path / "agent-started.txt").read_text(), "work began after p2\n")
        record = self.record(a["active"]["task_id"])
        self.assertEqual((record["preparing"], record["worktree"]), (False, str(path)))

    def test_the_relock_after_a_checkout_outwaits_a_busy_lock(self):
        shim = self.home / "git-shim"
        shim.write_text(SHIM)
        shim.chmod(0o755)
        a = self.claim()
        quick = {"HERMES_TASK_LOCK_WAIT": "0.2", "HERMES_TASK_GIT": str(shim)}
        proc = self.start_branch(a, "hermes/l", env=quick)
        with open(self.personal / ".task-lock", "ab") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)  # e.g. another task's long task-clear snapshot
            (self.home / "release").write_text("")
            time.sleep(1.5)  # well past HERMES_TASK_LOCK_WAIT
        out, err = proc.communicate(timeout=60)
        self.assertEqual(proc.returncode, 0, err)
        self.assertEqual(json.loads(out)["active"]["branch"], "hermes/l")
        self.assertFalse(self.record(a["active"]["task_id"])["preparing"])

    def test_symlinked_worktree_directories_are_never_followed(self):
        victim = self.home / "victim"
        (victim / "dir").mkdir(parents=True)
        (victim / "important.txt").write_text("not trash\n")
        (self.personal / ".worktrees").mkdir()
        (self.personal / ".worktrees/.trash").symlink_to(victim)
        self.task("task-status")
        a = self.claim()
        self.assertIn("symlink", self.branch(a, "hermes/a", code=2).stderr)
        self.assertEqual(sorted(p.name for p in victim.iterdir()), ["dir", "important.txt"])
        (self.personal / ".worktrees/.trash").unlink()
        outside = self.home / "outside"
        outside.mkdir()
        (self.personal / ".worktrees/tally").symlink_to(outside)
        self.assertIn("symlink", self.branch(a, "hermes/a", code=2).stderr)
        self.assertEqual(list(outside.iterdir()), [])

    def test_listing_shows_kept_trees_and_wip_refs_and_refs_are_never_overwritten(self):
        a, b = self.claim(thread(1)), self.claim(thread(2))
        wt_a = Path(self.branch(a, "hermes/a")["active"]["worktree"])
        (wt_a / "new.txt").write_text("a\n")
        wip = self.task("task-clear", "--id", a["active"]["task_id"])["wip_ref"]
        wt_b = Path(self.branch(b, "hermes/b")["active"]["worktree"])
        (wt_b / "new.txt").write_text("b\n")
        taken = f"refs/hermes/wip/{b['active']['task_id']}"
        self.git(self.base, "update-ref", taken, "upstream/main")
        cleared = self.task("task-clear", "--id", b["active"]["task_id"])
        self.assertEqual((cleared["wip_ref"], cleared["worktree_removed"]), (None, False))  # kept, not overwritten
        self.assertEqual(self.git(self.base, "rev-parse", taken), self.git(self.base, "rev-parse", "upstream/main"))
        listing = self.task("task-status", "--all")
        self.assertEqual(listing["kept"], [Path(cleared["kept"]).name])
        self.assertEqual(listing["wip_refs"], sorted([{"project": "tally", "ref": wip}, {"project": "tally", "ref": taken}],
                                                     key=lambda r: r["ref"]))


if __name__ == "__main__":
    unittest.main()
