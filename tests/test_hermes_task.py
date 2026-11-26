"""Exercise the installed task CLI contract without Hermes or stygies."""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


TOOL = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-task.py"
MATRIX = ("!room:matrix.example:8448", "$request")
OTHER_MATRIX = ("!opaque_room-id", "$event+/_=-")
SAME_ROOM = (MATRIX[0], "$other-thread")
OLD = "2024-01-01T00:00:00Z"
APP_PROJECTS = ("rust-app-template", "tally")


def row(timestamp, room, thread, project="tally", branch="pending", summary="Old request"):
    return "\t".join((timestamp, room, thread, project, branch, summary)) + "\n"


class TaskTools(unittest.TestCase):
    def setUp(self):
        home = Path(self.enterContext(TemporaryDirectory()))
        self.work = home / "personal"
        self.work.mkdir()
        self.current = self.work / ".current-task"
        self.queue = self.work / ".task-queue"
        self.env = {
            **os.environ,
            "HOME": str(home),
            "HERMES_TASK_APP_PROJECTS": json.dumps(APP_PROJECTS),
        }

    def invoke(self, *args, summary="", code=0, runner=(str(TOOL),)):
        result = subprocess.run(
            [sys.executable, "-I", "-B", *runner, *args],
            input=summary, text=True, encoding="utf-8", capture_output=True,
            env=self.env, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def task(self, *args, summary=""):
        return json.loads(self.invoke(*args, summary=summary).stdout)

    def state(self):
        return {path.name: path.read_bytes() for path in self.work.iterdir()}

    def claim_matrix(self, origin=MATRIX, project="tally", summary="Matrix task"):
        return self.task("task-claim", "--", *origin, project, "-", summary=summary)

    def claim_app(self, project="rust-app-template", summary="App task"):
        response = self.task("task-claim", "--app", "new", "--", project, "-", summary=summary)
        self.assertRegex(response["session_id"], r"\A[0-9a-f]{16}\Z")
        return response

    def test_matrix_cli_and_json_are_unchanged(self):
        self.assertEqual(self.task("task-status", "--"), {
            "result": "idle", "active": None, "age_seconds": None,
            "possibly_stale": False, "queue_position": None,
        })
        claim = self.claim_matrix()
        active = claim["active"]
        self.assertEqual(claim["result"], "claimed")
        self.assertEqual(set(claim), {"result", "active", "age_seconds", "possibly_stale", "queue_position"})
        self.assertEqual(active, dict(
            started_at=active["started_at"], room=MATRIX[0], thread=MATRIX[1],
            project="tally", branch="pending", summary="Matrix task",
        ))
        bare = self.task("task-status")
        del bare["age_seconds"]
        for origin, owned in ((MATRIX, True), (OTHER_MATRIX, False)):
            scoped = self.task("task-status", "--", *origin)
            self.assertIsInstance(scoped.pop("age_seconds"), int)
            self.assertEqual(scoped, {**bare, "owned": owned})
        self.assertEqual(self.claim_matrix(project="other", summary="Don't replace")["active"], active)
        queued = self.claim_matrix(OTHER_MATRIX, "rust-app-template")
        self.assertEqual((queued["result"], queued["queue_position"]), ("queued", 1))
        self.assertEqual(self.claim_matrix(OTHER_MATRIX, summary="Don't enqueue twice")["queue_position"], 1)
        self.assertEqual(self.task("task-status", "--", *OTHER_MATRIX)["queue_position"], 1)
        self.assertIsNone(self.task("task-status")["queue_position"])
        branch = self.task("task-branch", "--", *MATRIX, active["started_at"], "hermes/fix")
        self.assertEqual((branch["result"], branch["active"]["branch"]), ("updated", "hermes/fix"))
        promoted = self.task("task-done", "--", *MATRIX, active["started_at"])
        self.assertEqual((promoted["result"], promoted["active"]["room"], promoted["active"]["thread"]),
                         ("handoff", *OTHER_MATRIX))
        self.assertIsNone(self.task("task-status", "--", *OTHER_MATRIX)["queue_position"])
        self.assertEqual(self.task("task-clear", "--")["result"], "idle")
        self.assertEqual(self.state(), {})

    def test_threads_in_same_room_are_distinct_origins(self):
        active = self.claim_matrix()["active"]
        self.assertEqual(self.claim_matrix(OTHER_MATRIX)["queue_position"], 1)
        queued = self.claim_matrix(SAME_ROOM, summary="Same room, different task")
        self.assertEqual((queued["result"], queued["queue_position"]), ("queued", 2))
        before = self.state()
        retry = self.claim_matrix(SAME_ROOM, summary="Don't enqueue twice")
        self.assertEqual((retry["result"], retry["queue_position"]), ("queued", 2))
        owner = ("--", *SAME_ROOM, active["started_at"])
        self.invoke("task-done", *owner, code=2)
        self.invoke("task-branch", *owner, "hermes/fix", code=2)
        self.assertEqual(self.state(), before)
        self.assertIsNone(self.task("task-status", "--", *MATRIX)["queue_position"])

        # Once the unrelated head is removed, the next row is in the active
        # room but is not a duplicate of the active thread.
        head = self.task("task-status", "--queue")["queue"][0]
        self.task("task-drop", "--", "1", head["queued_at"])
        status = self.task("task-status", "--", *SAME_ROOM)
        self.assertEqual((status["owned"], status["queue_position"]), (False, 1))
        handoff = self.task("task-done", "--", *MATRIX, active["started_at"])
        self.assertEqual((handoff["result"], handoff["active"]["summary"]),
                         ("handoff", "Same room, different task"))

    def test_app_claim_branch_done_and_fresh_id(self):
        claim = self.claim_app(summary=" Don't expand $HOME or 'quotes'.\tTwo\r\nlines. ")
        session = claim["session_id"]
        active = claim["active"]
        stamp = active["started_at"]
        app = ("--app", session, "--")
        self.assertEqual(claim["result"], "claimed")
        self.assertTrue(claim["owned"])
        self.assertEqual(active, dict(
            started_at=stamp, origin_kind="app", session_id=session, project="rust-app-template",
            branch="pending", summary="Don't expand $HOME or 'quotes'. Two lines.",
        ))
        self.assertEqual(self.current.read_text(), row(
            stamp, f"app:{session}", "", "rust-app-template", summary=active["summary"],
        ))
        status = self.task("task-status", *app)
        self.assertTrue(status["owned"])
        self.assertEqual(status["active"], active)
        updated = self.task("task-branch", *app, stamp, "hermes/app")
        self.assertEqual((updated["result"], updated["active"]["branch"]), ("updated", "hermes/app"))
        self.assertTrue(updated["owned"])
        done = self.task("task-done", *app, stamp)
        self.assertEqual((done["result"], done["owned"]), ("idle", False))
        followup = self.claim_app("tally")
        self.assertNotEqual(followup["session_id"], session)
        self.invoke("task-done", *app, followup["active"]["started_at"], code=2)
        self.assertEqual(self.task("task-clear")["result"], "idle")
        self.assertEqual(self.state(), {})

    def test_mixed_queue_continuation_is_read_only_and_fifo(self):
        active = self.claim_matrix()["active"]
        first = self.claim_app()
        self.assertEqual((first["result"], first["queue_position"], first["active"]), ("queued", 1, active))
        self.assertFalse(first["owned"])
        self.assertEqual(self.claim_matrix(OTHER_MATRIX)["queue_position"], 2)
        third = self.claim_app("tally")
        self.assertEqual(third["queue_position"], 3)
        self.assertNotEqual(first["session_id"], third["session_id"])
        first_app = ("--app", first["session_id"])
        third_app = ("--app", third["session_id"])
        before = self.state()
        self.assertEqual(self.task("task-status", *first_app)["queue_position"], 1)
        self.assertEqual(self.task("task-status", "--", *OTHER_MATRIX)["queue_position"], 2)
        self.assertEqual(self.task("task-status", *third_app)["queue_position"], 3)
        self.assertEqual(self.state(), before)

        first_handoff = self.task("task-done", "--", *MATRIX, active["started_at"])
        app_active = first_handoff["active"]
        self.assertEqual(first_handoff["result"], "handoff")
        self.assertEqual(app_active, {"origin_kind": "app", "project": "rust-app-template"})
        status = self.task("task-status", *first_app)
        self.assertTrue(status["owned"])
        self.assertEqual(status["active"]["session_id"], first["session_id"])
        self.assertIsNone(status["queue_position"])
        for observer in ((), ("--", *OTHER_MATRIX), third_app):
            with self.subTest(observer=observer):
                reply = self.task("task-status", *observer)
                self.assertEqual(reply["active"], app_active)
                self.assertNotIn("session_id", reply)
                if observer:
                    self.assertFalse(reply["owned"])
        self.assertEqual(self.task("task-status", "--", *OTHER_MATRIX)["queue_position"], 1)

        second = self.task("task-done", *first_app, "--", status["active"]["started_at"])
        self.assertEqual((second["result"], second["active"]["thread"], second["owned"]),
                         ("handoff", OTHER_MATRIX[1], False))
        ended = self.task("task-status", *first_app)
        self.assertFalse(ended["owned"])
        self.assertIsNone(ended["queue_position"])
        third_handoff = self.task("task-clear")
        self.assertEqual((third_handoff["result"], third_handoff["active"]),
                         ("handoff", {"origin_kind": "app", "project": "tally"}))
        third_status = self.task("task-status", *third_app)
        self.assertTrue(third_status["owned"])
        self.assertEqual(third_status["active"]["session_id"], third["session_id"])
        self.assertEqual(self.task("task-done", *third_app, "--", third_status["active"]["started_at"])["result"], "idle")
        self.assertIsNone(self.task("task-status", *third_app)["queue_position"])
        self.assertEqual(self.state(), {})

    def test_mutations_require_matching_origin_and_timestamp(self):
        active = self.claim_app()["active"]
        app = ("--app", active["session_id"], "--")
        before = self.state()
        for owner in (("--", *MATRIX, active["started_at"]), (*app, OLD)):
            with self.subTest(owner=owner):
                for command in (("task-done", *owner), ("task-branch", *owner, "hermes/not-owned")):
                    self.assertIn("no longer owns", self.invoke(*command, code=2).stderr)
        self.assertEqual(self.state(), before)

        # An app task also cannot act on a Matrix holder, even with its timestamp.
        self.claim_matrix()
        matrix = self.task("task-clear")["active"]
        before = self.state()
        self.invoke("task-done", *app, matrix["started_at"], code=2)
        self.assertEqual(self.state(), before)

    def test_invalid_origins_and_reusing_app_id_do_not_write(self):
        session = self.claim_app()["session_id"]
        before = self.state()
        for value in ("", "new", "app:" + session, session.upper() + "G", "a" * 15, "a" * 17,
                      "../" + session, session + "\t", session + "\n", "é" * 16):
            with self.subTest(value=value):
                self.invoke("task-status", "--app", value, code=2)
        for command, tail in (("task-done", ()), ("task-branch", ("hermes/fix",))):
            err = self.invoke(command, "--app", "not-minted", "--", OLD, *tail, code=2).stderr
            self.assertIn("Invalid app task ID", err)
        for command in (
            ("task-status", "--app"), ("task-status", "--", MATRIX[0]),
            ("task-status", "--", "#alias", MATRIX[1]),
            ("task-status", "--", MATRIX[0], "not-an-event"),
            ("task-status", "--app", session, "--", *MATRIX),
            ("task-status", "--queue", "--", *MATRIX),
            ("task-status", "--queue", "--app", session),
            ("task-claim", "--app", "new", "--", *MATRIX, "tally", "-"),
            ("task-claim", "--app", session, "--", "tally", "-"),
            ("task-claim", "--", "tally", "-"),
            ("task-done", "--app", session, "--", *MATRIX, OLD),
            ("task-branch", "--app", session, "--", OLD),
            ("task-clear", "--app", session),
        ):
            with self.subTest(command=command):
                self.invoke(*command, summary="Don't change state", code=2)
        self.invoke("task-claim", "--app", "new", "--", "tally", "-", summary="\t\n", code=2)
        self.assertEqual(self.state(), before)

    def test_app_claim_requires_configured_basenames(self):
        for project in ("", ".", "..", "x/y", "x y", "x\tname", " tally", "tally2", "répo"):
            with self.subTest(project=project):
                self.invoke("task-claim", "--app", "new", "--", project, "-", summary="App task", code=2)
        for project in ("../tally", "..", ".hidden", "-tally"):
            with self.subTest(matrix_project=project):
                self.invoke("task-claim", "--", *MATRIX, project, "-", summary="Matrix task", code=2)
        del self.env["HERMES_TASK_APP_PROJECTS"]
        self.invoke("task-claim", "--app", "new", "--", "tally", "-", summary="App task", code=2)
        self.assertEqual(self.state(), {})
        self.assertEqual(self.claim_matrix(project="not-listed")["active"]["project"], "not-listed")

    def test_bad_allowlist_config_is_rejected_before_claim(self):
        for raw in ("[", '"tally"', '{"tally":true}', '["tally", 7]', "null"):
            with self.subTest(raw=raw):
                self.env["HERMES_TASK_APP_PROJECTS"] = raw
                result = self.invoke("task-claim", "--app", "new", "--", "tally", "-",
                                     summary="App task", code=2)
                self.assertEqual(result.stderr, "HERMES_TASK_APP_PROJECTS must be a JSON list of strings.\n")
                self.assertFalse(result.stdout)
        self.assertEqual(self.state(), {})

    def test_app_mint_retries_collisions_using_secrets(self):
        active_id, queued_id, fresh_id = ("1" * 16, "2" * 16, "3" * 16)
        self.current.write_text(row(OLD, f"app:{active_id}", ""))
        self.queue.write_text(row(OLD, f"app:{queued_id}", ""))
        before = self.state()
        # Inject collisions at the entropy source, not in the claim implementation.
        runner = ("-c", """
import runpy
import sys
from unittest.mock import patch

tool = sys.argv.pop(1)
ids = [sys.argv.pop(1) for _ in range(3)]
with patch("secrets.token_hex", side_effect=ids):
    runpy.run_path(tool, run_name="__main__")
""", str(TOOL), active_id, queued_id, fresh_id)
        result = self.invoke("task-claim", "--app", "new", "--", "tally", "-",
                             summary="New task", runner=runner)
        claim = json.loads(result.stdout)
        self.assertEqual((claim["result"], claim["session_id"], claim["queue_position"]),
                         ("queued", fresh_id, 2))
        self.assertEqual(claim["active"], {"origin_kind": "app", "project": "tally"})
        self.assertEqual(self.current.read_bytes(), before[".current-task"])
        self.assertEqual(self.task("task-status", "--app", queued_id)["queue_position"], 1)
        self.assertEqual(self.task("task-status", "--app", fresh_id)["queue_position"], 2)

    def test_drop_only_matching_queued_row(self):
        active = self.claim_app("tally")
        self.claim_matrix()
        queued = self.claim_app(summary="Pick this\trow")
        self.claim_matrix(OTHER_MATRIX)
        before = self.state()
        listing = self.task("task-status", "--queue")
        self.assertEqual(listing["active"], {"origin_kind": "app", "project": "tally"})
        queue = listing["queue"]
        first_at, third_at = (queue[i]["queued_at"] for i in (0, 2))
        queued_at = queued["queued_at"]
        self.assertEqual(queue, [
            dict(queue_position=1, origin_kind="matrix", project="tally",
                 queued_at=first_at, summary="Matrix task"),
            dict(queue_position=2, origin_kind="app", project="rust-app-template",
                 queued_at=queued_at, summary="Pick this row"),
            dict(queue_position=3, origin_kind="matrix", project="tally",
                 queued_at=third_at, summary="Matrix task"),
        ])
        for position, stamp in (("2", first_at), ("0", queued_at), ("4", queued_at), ("abc", queued_at)):
            with self.subTest(position=position, stamp=stamp):
                self.invoke("task-drop", "--", position, stamp, code=2)
        self.assertEqual(self.state(), before)
        dropped = self.task("task-drop", "--", "2", queued_at)
        self.assertEqual(dropped["result"], "dropped")
        self.assertEqual(dropped["active"], listing["active"])
        self.assertEqual(dropped["dropped"], {
            "origin_kind": "app", "project": "rust-app-template", "queued_at": queued_at,
        })
        self.assertEqual(self.current.read_bytes(), before[".current-task"])
        self.assertEqual(self.queue.read_bytes().splitlines(), [
            before[".task-queue"].splitlines()[i] for i in (0, 2)
        ])
        self.assertIsNone(self.task("task-status", "--app", queued["session_id"])["queue_position"])
        self.assertTrue(self.task("task-status", "--app", active["session_id"])["owned"])

    def test_handoff_invalidates_stale_drop_positions_and_promoted_key(self):
        active = self.claim_matrix(summary="Active task")["active"]
        promoted = self.claim_app("tally", "First tally task")
        orphan = self.claim_app("tally", "Orphaned tally task")
        self.claim_matrix(SAME_ROOM, summary="Live tally task")
        listing = self.task("task-status", "--queue")
        self.assertEqual(listing["active"], {
            "origin_kind": "matrix", "project": "tally", "summary": "Active task",
        })
        first, second, third = listing["queue"]
        self.assertEqual((first["queued_at"], second["queued_at"]),
                         (promoted["queued_at"], orphan["queued_at"]))
        self.assertEqual((first["summary"], second["summary"]),
                         ("First tally task", "Orphaned tally task"))
        self.assertEqual(len({row["queued_at"] for row in listing["queue"]}), 3)
        self.task("task-done", "--", *MATRIX, active["started_at"])

        before = self.state()
        for row in (first, second):
            with self.subTest(row=row):
                self.invoke("task-drop", "--", str(row["queue_position"]), row["queued_at"], code=2)
                self.assertEqual(self.state(), before)
        status = self.task("task-status", "--app", promoted["session_id"])
        self.assertTrue(status["owned"])
        self.assertNotEqual(status["active"]["started_at"], first["queued_at"])
        self.assertEqual(self.task("task-drop", "--", "1", orphan["queued_at"])["result"], "dropped")
        self.assertEqual(self.task("task-status", "--queue")["queue"], [
            {**third, "queue_position": 1},
        ])

    def test_new_queue_keys_do_not_reuse_a_live_timestamp(self):
        self.current.write_text(row(OLD, *MATRIX))
        self.queue.write_text(row("2024-01-01T00:00:00.000001Z", *OTHER_MATRIX))
        runner = ("-c", """
import datetime
import runpy
import sys

tool = sys.argv.pop(1)
frozen = datetime.datetime.fromisoformat(sys.argv.pop(1))
class FrozenDateTime(datetime.datetime):
    @classmethod
    def now(cls, tz=None):
        return frozen.astimezone(tz)

datetime.datetime = FrozenDateTime
runpy.run_path(tool, run_name="__main__")
""", str(TOOL), OLD)
        result = self.invoke("task-claim", "--app", "new", "--", "tally", "-",
                             summary="App task", runner=runner)
        claim = json.loads(result.stdout)
        self.assertEqual(claim["queued_at"], "2024-01-01T00:00:00.000002Z")
        promoted = self.invoke("task-done", "--", *MATRIX, OLD, runner=runner)
        self.assertEqual(json.loads(promoted.stdout)["active"]["started_at"],
                         "2024-01-01T00:00:00.000003Z")

    def test_legacy_files_remain_readable_and_mix_with_app_rows(self):
        self.current.write_text(row(OLD, *MATRIX, branch="hermes/old"))
        self.queue.write_text(row(OLD, *OTHER_MATRIX))
        before = self.state()
        status = self.task("task-status", "--", *OTHER_MATRIX)
        self.assertEqual((status["active"]["branch"], status["queue_position"]), ("hermes/old", 1))
        self.assertTrue(status["possibly_stale"])
        self.assertEqual(self.state(), before)

        app = self.claim_app()
        self.assertEqual(app["queue_position"], 2)
        self.assertTrue(self.queue.read_bytes().startswith(before[".task-queue"]))
        matrix = self.task("task-done", "--", *MATRIX, OLD)["active"]
        self.assertEqual(matrix["thread"], OTHER_MATRIX[1])
        self.assertNotEqual(matrix["started_at"], OLD)
        self.invoke("task-done", "--", *OTHER_MATRIX, OLD, code=2)
        self.assertEqual(self.task("task-clear")["active"], {
            "origin_kind": "app", "project": "rust-app-template",
        })
        self.assertTrue(self.task("task-status", "--app", app["session_id"])["owned"])

    def test_interrupted_promotion_does_not_queue_same_app_again(self):
        session = "0123456789abcdef"
        self.current.write_text(row(OLD, f"app:{session}", ""))
        self.queue.write_text(row(OLD, f"app:{session}", "") + row(OLD, *MATRIX))
        before = self.state()
        self.assertIsNone(self.task("task-status", "--app", session)["queue_position"])
        self.assertEqual(self.task("task-status", "--", *MATRIX)["queue_position"], 1)
        self.assertEqual(self.state(), before)
        promoted = self.task("task-done", "--app", session, "--", OLD)
        self.assertEqual(promoted["active"]["thread"], MATRIX[1])
        self.assertFalse(self.queue.exists())

    def test_invalid_app_rows_are_not_silently_dropped(self):
        self.queue.write_text(row(OLD, *MATRIX))
        for room, thread in (("app:not-minted", ""), ("app:0123456789abcdef", "$not-empty")):
            with self.subTest(room=room, thread=thread):
                corrupt = row(OLD, room, thread)
                self.current.write_text(corrupt)
                before = self.state()
                self.assertIn("invalid app origin", self.invoke("task-status", code=2).stderr)
                self.assertEqual(self.state(), before)
                cleared = self.invoke("task-clear")
                self.assertIn("Moved invalid task state", cleared.stderr)
                promoted = json.loads(cleared.stdout)
                self.assertEqual((promoted["result"], promoted["active"]["thread"]), ("handoff", MATRIX[1]))
                self.assertIn(corrupt, [path.read_text() for path in self.work.glob(".current-task.bad-*")])
                # Restore the valid queue fixture for the next corrupt slot.
                self.queue.write_text(row(OLD, *MATRIX))


APP_ONLY = "app-only-repo"


class TaskToolsWithAppOnly(TaskTools):
    """Every TaskTools test again, with a roomless project configured: projects with rooms behave the same."""

    def setUp(self):
        super().setUp()
        self.env["HERMES_TASK_APP_PROJECTS"] = json.dumps([*APP_PROJECTS, APP_ONLY])
        self.env["HERMES_TASK_APP_ONLY_PROJECTS"] = json.dumps([APP_ONLY])

    def test_matrix_claim_of_app_only_project_is_refused(self):
        for origin in (MATRIX, OTHER_MATRIX):
            with self.subTest(origin=origin):
                result = self.invoke("task-claim", "--", *origin, APP_ONLY, "-", summary="Matrix task", code=2)
                self.assertEqual(result.stderr, "Project is app-only; claim it from the Hermes app.\n")
                self.assertFalse(result.stdout)
        self.assertEqual(self.state(), {})
        # Refused while a task holds the slot too: nothing is queued.
        active = self.claim_matrix()["active"]
        before = self.state()
        self.invoke("task-claim", "--", *OTHER_MATRIX, APP_ONLY, "-", summary="Matrix task", code=2)
        self.assertEqual(self.state(), before)
        self.assertEqual(self.task("task-done", "--", *MATRIX, active["started_at"])["result"], "idle")

    def test_app_claim_of_app_only_project_works(self):
        claim = self.claim_app(APP_ONLY)
        self.assertEqual(claim["result"], "claimed")
        self.assertEqual(claim["active"]["project"], APP_ONLY)
        session = claim["session_id"]
        started = claim["active"]["started_at"]
        branch = self.task("task-branch", "--app", session, "--", started, "hermes/app-only")
        self.assertEqual(branch["active"]["branch"], "hermes/app-only")
        # A Matrix claim of a project with a room still queues behind it.
        queued = self.claim_matrix()
        self.assertEqual((queued["result"], queued["queue_position"]), ("queued", 1))
        promoted = self.task("task-done", "--app", session, "--", started)
        self.assertEqual((promoted["result"], promoted["active"]["room"]), ("handoff", MATRIX[0]))

    def test_bad_app_only_config_is_rejected_before_claim(self):
        for raw in ("[", f'"{APP_ONLY}"', "null", "[7]"):
            with self.subTest(raw=raw):
                self.env["HERMES_TASK_APP_ONLY_PROJECTS"] = raw
                for args in (("--", *MATRIX, "tally", "-"), ("--app", "new", "--", APP_ONLY, "-")):
                    result = self.invoke("task-claim", *args, summary="Task", code=2)
                    self.assertEqual(result.stderr, "HERMES_TASK_APP_ONLY_PROJECTS must be a JSON list of strings.\n")
        self.assertEqual(self.state(), {})


DEVZERO_ROOM = "!devzero-room:matrix.example"
CODILAS_ROOM = "!codilas-room:matrix.example"
BRANCH_PATTERN = r"^(feature|fix|chore)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9][a-z0-9-]*$"


class CompanySlots(unittest.TestCase):
    """The work coder's per-company wrappers: same script, its own state dir and allowlists."""

    def setUp(self):
        self.home = Path(self.enterContext(TemporaryDirectory()))
        self.slots = {
            "devzero": (self.home / "work/.tasks/devzero", DEVZERO_ROOM, ("api", "web")),
            "codilas": (self.home / "work/.tasks/codilas", CODILAS_ROOM, ("backend",)),
        }
        for state, _, _ in self.slots.values():
            state.mkdir(parents=True)

    def env(self, company):
        state, room, repos = self.slots[company]
        return {
            **os.environ,
            "HOME": str(self.home),
            "HERMES_TASK_STATE_DIR": str(state),
            "HERMES_TASK_APP_PROJECTS": json.dumps(repos),
            "HERMES_TASK_PROJECTS": json.dumps(repos),
            "HERMES_TASK_ROOMS": json.dumps([room]),
            "HERMES_TASK_BRANCH_PATTERN": BRANCH_PATTERN,
        }

    def invoke(self, company, *args, summary="", code=0, env=None):
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(TOOL), *args],
            input=summary, text=True, encoding="utf-8", capture_output=True,
            env=env or self.env(company), timeout=10, check=False,
        )
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def task(self, company, *args, summary=""):
        return json.loads(self.invoke(company, *args, summary=summary).stdout)

    def state(self, company):
        state = self.slots[company][0]
        return {path.name: path.read_bytes() for path in state.iterdir()}

    def test_state_lives_in_the_company_dir_never_in_personal(self):
        claim = self.task("devzero", "task-claim", "--", DEVZERO_ROOM, "$t1", "api", "-", summary="DEV-1 task")
        self.assertEqual(claim["result"], "claimed")
        self.assertEqual(set(self.state("devzero")), {".current-task"})
        self.assertFalse((self.home / "personal").exists())
        self.assertEqual(self.state("codilas"), {})

    def test_company_slots_are_independent(self):
        dz = self.task("devzero", "task-claim", "--", DEVZERO_ROOM, "$t1", "api", "-", summary="DEV-1")
        cz = self.task("codilas", "task-claim", "--", CODILAS_ROOM, "$t2", "backend", "-", summary="COD-1")
        self.assertEqual((dz["result"], cz["result"]), ("claimed", "claimed"))
        queued = self.task("devzero", "task-claim", "--", DEVZERO_ROOM, "$t3", "web", "-", summary="DEV-2")
        self.assertEqual((queued["result"], queued["queue_position"]), ("queued", 1))
        self.assertNotIn(".task-queue", self.state("codilas"))
        done = self.task("codilas", "task-done", "--", CODILAS_ROOM, "$t2", cz["active"]["started_at"])
        self.assertEqual(done["result"], "idle")
        status = self.task("devzero", "task-status", "--", DEVZERO_ROOM, "$t1")
        self.assertTrue(status["owned"])
        handoff = self.task("devzero", "task-done", "--", DEVZERO_ROOM, "$t1", dz["active"]["started_at"])
        self.assertEqual((handoff["result"], handoff["active"]["thread"]), ("handoff", "$t3"))

    def test_project_allowlist_covers_matrix_and_app_claims(self):
        for args in (("--", DEVZERO_ROOM, "$t1", "backend", "-"), ("--app", "new", "--", "backend", "-")):
            with self.subTest(args=args):
                result = self.invoke("devzero", "task-claim", *args, summary="x", code=2)
                self.assertIn("not enabled", result.stderr)
        self.assertEqual(self.state("devzero"), {})

    def test_room_allowlist_refuses_other_rooms(self):
        claim = self.task("devzero", "task-claim", "--", DEVZERO_ROOM, "$t1", "api", "-", summary="DEV-1")
        before = self.state("devzero")
        stamp = claim["active"]["started_at"]
        for args in (
            ("task-claim", "--", CODILAS_ROOM, "$t1", "api", "-"),
            ("task-status", "--", CODILAS_ROOM, "$t1"),
            ("task-branch", "--", CODILAS_ROOM, "$t1", stamp, "feature/DEV-1-x"),
            ("task-done", "--", CODILAS_ROOM, "$t1", stamp),
        ):
            with self.subTest(action=args[0]):
                result = self.invoke("devzero", *args, summary="x", code=2)
                self.assertEqual(result.stderr, "This Matrix room does not use these task commands.\n")
        self.assertEqual(self.state("devzero"), before)

    def test_branch_pattern_is_enforced(self):
        claim = self.task("devzero", "task-claim", "--", DEVZERO_ROOM, "$t1", "api", "-", summary="DEV-1")
        origin = ("--", DEVZERO_ROOM, "$t1", claim["active"]["started_at"])
        before = self.state("devzero")
        for branch in ("hermes/x", "main", "feature/dev-1-x", "feature/DEV-x", "feat/DEV-1-x",
                       "feature/DEV-1-Fix", "feature/DEV-1-", "pending", "feature/DEV-1-x/y"):
            with self.subTest(branch=branch):
                result = self.invoke("devzero", "task-branch", *origin, branch, code=2)
                self.assertEqual(result.stderr, "Branch name does not match the required pattern.\n")
        self.assertEqual(self.state("devzero"), before)
        for branch in ("feature/DEV-1-fix-login", "fix/AB2-10-x", "chore/DEV-123-a-1"):
            with self.subTest(branch=branch):
                self.assertEqual(self.task("devzero", "task-branch", *origin, branch)["active"]["branch"], branch)

    def test_app_cycle_in_a_company_slot(self):
        claim = self.task("codilas", "task-claim", "--app", "new", "--", "backend", "-", summary="COD-7")
        session = claim["session_id"]
        app = ("--app", session, "--")
        stamp = claim["active"]["started_at"]
        branch = self.task("codilas", "task-branch", *app, stamp, "fix/COD-7-null-check")
        self.assertEqual(branch["active"]["branch"], "fix/COD-7-null-check")
        self.assertTrue(self.task("codilas", "task-status", *app)["owned"])
        self.assertEqual(self.task("codilas", "task-done", *app, stamp)["result"], "idle")
        self.assertEqual(self.state("codilas"), {})

    def test_bad_company_env_exits_before_any_write(self):
        cases = {
            "HERMES_TASK_STATE_DIR": ("relative/dir", "HERMES_TASK_STATE_DIR must be an absolute path.\n"),
            "HERMES_TASK_PROJECTS": ('"api"', "HERMES_TASK_PROJECTS must be a JSON list of strings.\n"),
            "HERMES_TASK_ROOMS": ("[1]", "HERMES_TASK_ROOMS must be a JSON list of strings.\n"),
            "HERMES_TASK_BRANCH_PATTERN": ("(", "HERMES_TASK_BRANCH_PATTERN must be a valid regular expression.\n"),
        }
        for name, (value, message) in cases.items():
            with self.subTest(name=name):
                env = {**self.env("devzero"), name: value}
                result = self.invoke("devzero", "task-claim", "--", DEVZERO_ROOM, "$t1", "api", "-",
                                     summary="x", code=2, env=env)
                self.assertEqual(result.stderr, message)
        self.assertEqual(self.state("devzero"), {})
        self.assertFalse((self.home / "personal").exists())


if __name__ == "__main__":
    unittest.main()
