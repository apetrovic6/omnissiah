#!/usr/bin/env python3
"""Loopback Forgejo contract and fixed-slot lifecycle tests (no real credentials or units)."""

import contextlib
import http.client
import importlib.util
import io
import json
import os
import stat
import subprocess
import tempfile
import threading
import unittest
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

spec = importlib.util.spec_from_file_location("dispatcher", Path(__file__).with_name("_forgejo-ephemeral-dispatcher.py"))
D = importlib.util.module_from_spec(spec)
spec.loader.exec_module(D)

USER = "/api/v1/user"
RUNNERS = USER + "/actions/runners"
JOBS = RUNNERS + "/jobs?labels=nix-eph"
LIST = RUNNERS + "?visible=false&page={}&limit=50"
VM = "microvm@ryza-eph-1.service"
REPO, OWNER = 17, 42
PAT = "synthetic-dispatcher-pat-not-a-secret"
TOKEN = "synthetic-ephemeral-runner-token-not-a-secret"
REPO_NAME = "rust-app-template"
REPOSITORY = f"/api/v1/repos/manjo/{REPO_NAME}"
TASKS = REPOSITORY + "/actions/tasks?page={}&limit=50"
RUN = REPOSITORY + "/actions/runs?run_number={}&limit=50"
HERMES = 77
# Synthetic, shaped like the real files (nix-store --generate-binary-cache-key; reliquary-ncps netrc).
SIGNING_SECRET = "c3ludGhldGljLXNpZ25pbmcta2V5LW5vdC1hLXNlY3JldC1ub3QtYS1zZWNyZXQtcGFkZGluZy1wYWRkaW5nLXg="
SIGNING_KEY = f"ci.noosphere.uk-1:{SIGNING_SECRET}".encode()
NETRC_PASSWORD = "0123456789abcdef-synthetic-netrc-password-not-a-secret"
NETRC = f"machine ncps.noosphere.uk\nlogin forgejo-runner\npassword {NETRC_PASSWORD}\n".encode()


def job(job_id=1, handle="opaque/attempt-1", **fields):
    return {
        "id": job_id,
        "handle": handle,
        "owner_id": OWNER,
        "repo_id": REPO,
        "status": "waiting",
        "runs_on": ["nix-eph"],
        "attempt": 1,
        "task_id": 0,
    } | fields


def uuid_for(number):
    return f"00000000-0000-4000-a000-{number:012x}"


def task(task_id=71, run_number=7, **fields):
    return {"id": task_id, "run_number": run_number, "head_sha": "c0ffee", "workflow_id": "ci.yml", "status": "running"} | fields


def run(index=7, **fields):
    """A master push merged by manjo, as Forgejo v15.0.12 serializes it (services/convert/action.go)."""
    return {
        "id": 500 + index,
        "index_in_repo": index,
        "title": TOKEN,  # Job-controlled text must never reach the logs.
        "repository": {"id": REPO, "name": REPO_NAME, "owner": {"id": OWNER, "login": "manjo"}},
        "trigger_user": {"id": OWNER, "login": "manjo"},
        "is_fork_pull_request": False,
        "need_approval": False,
        "approved_by": 0,
        "event": "push",
        "trigger_event": "push",
        "ScheduleID": 0,
        "prettyref": "master",
        "commit_sha": "c0ffee",
        "workflow_id": "ci.yml",
        "status": "running",
        "event_payload": "{}",
    } | fields


class FakeForge:
    def __init__(self):
        self.calls = []
        self.faults = {}
        self.identity = {"login": "manjo", "id": OWNER}
        self.jobs = None
        self.runners = {}
        self.next_id = 100
        self.page_size = 50
        self.next_link = None
        self.observe_post = None
        self.repository = {"id": REPO, "name": REPO_NAME, "owner": {"id": OWNER, "login": "manjo"}}
        self.tasks = []
        self.runs = []

        class Handler(BaseHTTPRequestHandler):
            def respond(handler):
                data = handler.rfile.read(int(handler.headers.get("Content-Length", "0")))
                payload = json.loads(data) if data else None
                self.calls.append((handler.command, handler.path, handler.headers, payload))
                status, body, headers = self.route(handler.command, handler.path, payload)
                if isinstance(body, threading.Event):
                    body.wait(5)
                    handler.close_connection = True
                    return
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                if status == 204:
                    data = b""
                try:
                    handler.send_response(status)
                    handler.send_header("Content-Type", "application/json")
                    handler.send_header("Content-Length", str(len(data)))
                    for name, value in headers.items():
                        handler.send_header(name, value)
                    handler.end_headers()
                    handler.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            do_GET = do_POST = do_DELETE = respond

            def log_message(self, *_args):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def connect(self):
        return http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def reply_once(self, method, path, status, body=None, **headers):
        self.faults.setdefault((method, path), deque()).append((status, body, headers))

    def add_runner(self, name, **fields):
        runner_id = self.next_id
        self.next_id += 1
        self.runners[runner_id] = {
            "id": runner_id,
            "uuid": uuid_for(runner_id),
            "name": name,
            "owner_id": OWNER,
            "repo_id": 0,
            "ephemeral": True,
        } | fields
        return runner_id

    def route(self, method, path, payload):
        if scripted := self.faults.get((method, path)):
            return scripted.popleft()
        if method == "GET" and path == USER:
            return 200, self.identity, {}
        if method == "GET" and path == JOBS:
            return 200, self.jobs, {}
        if method == "GET" and path.startswith(RUNNERS + "?"):
            query = parse_qs(urlsplit(path).query)
            if query.get("visible") != ["false"] or query.get("limit") != ["50"]:
                return 400, {"error": "unexpected runner inventory query"}, {}
            page = int(query["page"][0])
            end = page * self.page_size
            headers = {"X-Total-Count": str(len(self.runners))}
            if end < len(self.runners):
                link = self.next_link or self.url + LIST.format(page + 1)
                headers["Link"] = f'<{link}>; rel="next"'
            return 200, list(self.runners.values())[end - self.page_size : end], headers
        if method == "POST" and path == RUNNERS:
            if self.observe_post is not None:
                self.observe_post()
            if payload.keys() != {"name", "ephemeral"} or payload["ephemeral"] is not True:
                return 400, {"error": "unexpected registration payload"}, {}
            runner_id = self.add_runner(payload["name"])
            return 201, {"id": runner_id, "uuid": uuid_for(runner_id), "token": TOKEN}, {}
        if method == "DELETE" and path.startswith(RUNNERS + "/"):
            runner_id = int(path.rsplit("/", 1)[1])
            return (204 if self.runners.pop(runner_id, None) is not None else 404), None, {}
        if method == "GET" and path == REPOSITORY:
            return 200, self.repository, {}
        if method == "GET" and path.startswith(REPOSITORY + "/actions/tasks?"):
            query = parse_qs(urlsplit(path).query)
            if query.get("limit") != ["50"]:
                return 400, {"error": "unexpected task query"}, {}
            page = int(query["page"][0])
            rows = sorted(self.tasks, key=lambda row: -row["id"])
            return 200, {"total_count": len(rows), "workflow_runs": rows[(page - 1) * 50 : page * 50]}, {}
        if method == "GET" and path.startswith(REPOSITORY + "/actions/runs?"):
            query = parse_qs(urlsplit(path).query)
            if query.get("limit") != ["50"] or "status" in query:
                return 400, {"error": "unexpected run query"}, {}
            rows = [row for row in self.runs if row["index_in_repo"] == int(query["run_number"][0])]
            return 200, {"total_count": len(rows), "workflow_runs": rows}, {}
        return 404, {"error": "unexpected request"}, {}

    def paths(self, method=None):
        return [path for verb, path, _, _ in self.calls if method is None or method == verb]


class Crash(BaseException):
    pass


class FakeClock:
    now = 0

    def monotonic(self):
        return self.now

    def wall(self):
        return 1_800_000_000 + self.now


class FakeSystemctl:
    def __init__(self):
        self.states = {}
        self.calls = []
        self.start_mode = "queued"
        self.on_show = None
        self.on_start = None
        self.on_reset = None
        self.reset_fails = 0

    def set(self, unit=VM, *, active="inactive", pending="", result="success", loaded="loaded"):
        self.states[unit] = f"LoadState={loaded}\nActiveState={active}\nJob={pending}\nResult={result}\n".encode()

    def run(self, argv, **options):
        self.calls.append(argv)
        assert options["check"] and options["timeout"] and options["stderr"] == subprocess.DEVNULL
        assert argv[:3] == ("systemctl", "--system", "--no-pager")
        if "show" in argv:
            assert "--all" in argv and "--property=LoadState,ActiveState,Job,Result" in argv
            unit = argv[-1]
            if self.on_show:
                self.on_show(unit)
            data = self.states.get(unit, b"LoadState=loaded\nActiveState=inactive\nJob=\nResult=success\n")
            return subprocess.CompletedProcess(argv, 0, stdout=data)
        if "reset-failed" in argv:
            assert argv == ("systemctl", "--system", "--no-pager", "reset-failed", VM), argv
            if self.on_reset:
                self.on_reset()
            if self.reset_fails:
                self.reset_fails -= 1
                raise subprocess.CalledProcessError(1, argv)
            self.set()
            return subprocess.CompletedProcess(argv, 0, stdout=b"")
        assert "--no-block" in argv
        if "start" in argv:
            assert argv[-2:] == ("start", VM) and "--job-mode=fail" in argv
            if self.on_start:
                self.on_start()
            if self.start_mode == "failed":
                raise subprocess.CalledProcessError(1, argv, stderr=TOKEN.encode())
            self.set(pending="71")
            if self.start_mode == "uncertain":
                raise subprocess.TimeoutExpired(argv, options["timeout"], stderr=TOKEN.encode())
            if self.start_mode == "crash":
                raise Crash
        else:
            assert "stop" in argv
            units = argv[argv.index("stop") + 1 :]
            assert units == (VM,) or all(unit in D.SUPPORT for unit in units)
            for unit in units:
                self.set(unit, active="deactivating", pending="72")
        return subprocess.CompletedProcess(argv, 0, stdout=b"")

    def mutations(self, verb=None):
        return [args for args in self.calls if (verb in args if verb else "show" not in args)]


class DispatcherTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.state_dir = root / "state"
        self.vm_dir = root / "vm"
        self.credential_dir = root / "credentials" / "ryza-eph-1"
        for directory in (self.state_dir, self.vm_dir, self.credential_dir.parent):
            directory.mkdir(mode=0o700)
        self.pat_file = root / "forgejo-pat"
        self.pause = root / "pause"
        self.pat_file.write_text(PAT + "\n")
        self.forge = FakeForge()
        self.addCleanup(self.forge.close)
        self.system = FakeSystemctl()
        self.files = D.SlotFiles(self.vm_dir, self.credential_dir, os.getuid(), os.getgid())
        self.clock = FakeClock()
        self.logs = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.logs))
        self.restart()

    def tearDown(self):
        surface = self.logs.getvalue() + repr(self.system.calls)
        for state_file in self.state_dir.glob("state.json*"):
            surface += state_file.read_text()
        self.assertFalse(PAT in surface or TOKEN in surface, "credential found outside the HTTP header or slot staging")

    def restart(self):
        self.dispatcher = D.Dispatcher(
            REPO,
            D.Forgejo(self.pat_file, self.forge.connect),
            D.Systemctl(self.system.run),
            self.files,
            D.Store(self.state_dir),
            self.clock.monotonic,
            self.clock.wall,
            pause=self.pause,
        )

    def tick(self, advance=0):
        self.clock.now += advance
        return self.dispatcher.tick()

    def state(self):
        return json.loads((self.state_dir / "state.json").read_text())

    def leave_images(self):
        for name in ("nix-store-overlay.img", "var.img"):
            (self.vm_dir / name).touch()

    def assert_scrubbed(self):
        self.assertFalse((self.vm_dir / "nix-store-overlay.img").exists())
        self.assertFalse((self.vm_dir / "var.img").exists())
        self.assertFalse(self.credential_dir.exists())
        self.assertFalse(self.files.staging.exists())

    def test_contract_oldest_exact_waiting_handle_then_next(self):
        first = job(14)
        second = job(23, "another-attempt")
        self.forge.jobs = [
            second, first, first,
            job(6, "wrong-label", runs_on=["nix-eph", "another"]),
            job(5, "wrong-repository", repo_id=55),
            job(4, "already-assigned", status="running", task_id=8),
        ]
        posted, started = [], []
        self.forge.observe_post = lambda: posted.append(self.state())
        self.system.on_start = lambda: started.append(self.state())
        self.tick()
        active = self.state()["active"]
        name = active["name"]
        self.assertEqual([USER, LIST.format(1), JOBS, RUNNERS], self.forge.paths())
        self.assertTrue(all(headers.get("Authorization") == "token " + PAT for _, _, headers, _ in self.forge.calls))
        self.assertTrue(all(headers.get("Accept") == "application/json" for _, _, headers, _ in self.forge.calls))
        _, _, headers, payload = self.forge.calls[-1]
        self.assertEqual("application/json", headers["Content-Type"])
        self.assertEqual({"name": name, "ephemeral": True}, payload)
        self.assertRegex(name, r"^eph-[0-9a-f]{12}-ryza-[0-9a-f]{32}$")
        self.assertEqual(OWNER, posted[0]["owner_id"])
        self.assertEqual("intent", posted[0]["active"]["phase"])
        self.assertEqual(first["handle"], posted[0]["active"]["handle"])
        self.assertIsNone(posted[0]["active"]["runner"])
        self.assertEqual(active, started[0]["active"])
        self.assertEqual("start", active["phase"])
        self.assertEqual({"id": 100, "uuid": uuid_for(100)}, active["runner"])
        self.assertEqual(self.clock.wall(), active["queued_at"])
        self.assertEqual(0o600, stat.S_IMODE((self.state_dir / "state.json").stat().st_mode))
        self.assertEqual(0o700, stat.S_IMODE(self.credential_dir.stat().st_mode))
        self.assertEqual({"runner-uuid", "runner-token", "job-handle"}, {path.name for path in self.credential_dir.iterdir()})
        self.assertEqual(uuid_for(100), (self.credential_dir / "runner-uuid").read_text())
        self.assertTrue((self.credential_dir / "runner-token").read_text() == TOKEN)
        self.assertEqual(first["handle"], (self.credential_dir / "job-handle").read_text())
        for file in self.credential_dir.iterdir():
            info = file.stat()
            self.assertEqual((0o400, os.getuid(), os.getgid()), (stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid))
        self.assertFalse(self.files.staging.exists())

        self.leave_images()
        self.system.set(active="active")
        self.tick(7)
        self.assertEqual(1, len(self.system.mutations("start")))
        self.system.set()
        self.tick(7)
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS, RUNNERS], self.forge.paths("POST"))
        self.assertEqual(second["handle"], (self.credential_dir / "job-handle").read_text())
        self.assertEqual([first["handle"]], self.state()["retired"])
        self.assertFalse((self.vm_dir / "var.img").exists())

    def test_null_and_bad_job_response_do_not_allocate(self):
        self.tick()
        self.assertEqual([USER, LIST.format(1), JOBS], self.forge.paths())
        self.forge.jobs = {"error": PAT}
        self.tick(7)
        self.assertIn("unexpected response", self.logs.getvalue())
        self.assertEqual([], self.forge.paths("POST"))
        self.assertEqual([], self.system.mutations())

    def test_unavailable_api_leaves_hard_timeout_to_systemd(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.forge.reply_once("GET", JOBS, 503)
        self.leave_images()
        self.restart()
        self.tick(D.VM_DEADLINE + 1)
        self.assertTrue(self.credential_dir.exists())
        self.assertTrue((self.vm_dir / "var.img").exists())
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertEqual([], self.system.mutations("stop"))
        self.assertIn("past its recorded deadline", self.logs.getvalue())
        self.system.set(active="deactivating", pending="8", result="timeout")
        self.tick(7)
        self.assertTrue(self.credential_dir.exists())
        self.system.set(active="failed", result="timeout")
        self.tick(7)
        self.assert_scrubbed()
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assertIn("VM idle (timeout)", self.logs.getvalue())
        self.assertIsNone(self.state()["active"])

    def test_cancelled_before_declare_stops_vm_at_busy_poll_then_cleans(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="activating", pending="71")
        self.leave_images()
        self.tick(7)
        self.forge.jobs = None
        calls = self.forge.paths()
        self.tick(D.BUSY_POLL_FAST - 1)
        self.assertEqual(calls, self.forge.paths())
        self.tick(1)
        self.assertEqual(calls + [USER, JOBS], self.forge.paths())
        self.assertEqual([], self.system.mutations("stop"))
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(calls + [USER, JOBS, USER, JOBS], self.forge.paths())
        [stop] = self.system.mutations("stop")
        self.assertEqual(("stop", VM), stop[-2:])
        self.assertIn("target absent from consecutive job polls", self.logs.getvalue())
        self.tick(7)
        self.assertTrue((self.vm_dir / "var.img").exists())
        self.assertTrue(self.credential_dir.exists())
        self.assertEqual([], self.forge.paths("DELETE"))
        self.system.set()
        self.tick(7)
        self.assert_scrubbed()
        self.assertIsNone(self.state()["active"])
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))

    def test_cancelled_after_declare_frees_slot_for_waiting_job(self):
        self.forge.jobs = [job(), job(2, "other")]
        self.tick()
        self.system.set(active="active")
        self.forge.runners[100].update(status="idle", version="13.2.1", labels=["nix-eph"])
        self.forge.jobs = [job(2, "other")]
        self.tick(7)
        self.assertEqual([], self.system.mutations("stop"))
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(1, len(self.system.mutations("stop")))
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertNotIn(RUNNERS + "/100", self.forge.paths("GET"))
        self.system.set()
        self.tick(7)
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS, RUNNERS], self.forge.paths("POST"))
        self.assertEqual("other", self.state()["active"]["handle"])

    def test_cancel_during_boot_queues_one_stop_then_resets_the_timeout_failure(self):
        # Live 2026-11-25: cancelled before pickup, the booting guest ignored the ACPI powerdown, the
        # stop was logged on every poll while deactivating, and the unit ended failed/timeout.
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="activating", pending="71")
        self.leave_images()
        self.tick(7)
        self.forge.jobs = None
        self.tick(D.BUSY_POLL_FAST)
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(1, len(self.system.mutations("stop")))
        for _ in range(3):  # Deactivating for TimeoutStopSec: no second stop, no second log.
            self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(1, len(self.system.mutations("stop")))
        self.assertEqual(1, self.logs.getvalue().count("queued VM stop"))
        self.assertEqual([], self.system.mutations("reset-failed"))

        scrubbed_first = []
        self.system.on_reset = lambda: scrubbed_first.append(
            not (self.vm_dir / "var.img").exists() and not self.credential_dir.exists()
        )
        self.system.set(active="failed", result="timeout")
        self.tick(7)
        self.assertEqual([True], scrubbed_first)
        self.assertEqual(
            [("systemctl", "--system", "--no-pager", "reset-failed", VM)], self.system.mutations("reset-failed")
        )
        self.assertIn(f"reset {VM} after it ended with result timeout", self.logs.getvalue())
        self.assert_scrubbed()
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assertIsNone(self.state()["active"])
        self.tick(7)
        self.assertEqual(1, len(self.system.mutations("reset-failed")))  # Result is success again.

    def test_stop_is_requeued_only_if_the_slot_is_still_busy_after_the_retry_window(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.tick(7)
        self.forge.jobs = None
        self.tick(D.BUSY_POLL_FAST)
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(1, len(self.system.mutations("stop")))
        self.system.set(active="active")  # The stop job was lost; the slot is still running.
        elapsed = 0
        while elapsed + D.BUSY_POLL_FAST < D.STOP_RETRY:
            self.tick(D.BUSY_POLL_FAST)
            elapsed += D.BUSY_POLL_FAST
        self.assertEqual(1, len(self.system.mutations("stop")))
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(2, len(self.system.mutations("stop")))
        self.assertEqual(2, self.logs.getvalue().count("queued VM stop"))

    def test_reset_failed_error_is_logged_and_retried_without_blocking_cleanup(self):
        self.forge.jobs = [job()]
        self.tick()
        self.leave_images()
        self.system.set(active="failed", result="exit-code")
        self.system.reset_fails = 1
        self.tick(7)
        self.assert_scrubbed()
        self.assertIn("systemctl reset-failed failed or timed out", self.logs.getvalue())
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.tick(7)
        self.assertEqual(2, len(self.system.mutations("reset-failed")))
        self.assertIn(f"reset {VM} after it ended with result exit-code", self.logs.getvalue())

    def test_clean_exit_is_not_reset(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.tick(7)
        self.system.set()
        self.tick(7)
        self.tick(7)
        self.assertEqual([], self.system.mutations("reset-failed"))
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))

    def test_running_exact_handle_resets_absence_streak(self):
        first = job()
        self.forge.jobs = [first]
        self.tick()
        self.system.set(active="active")
        similar = job(handle=first["handle"] + "0")
        self.forge.jobs = [similar]
        self.tick(7)
        self.forge.jobs = [first | {"status": "running", "task_id": 71}]
        self.tick(D.BUSY_POLL_FAST)
        self.forge.jobs = [similar]
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual([], self.system.mutations("stop"))
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(1, len(self.system.mutations("stop")))

    def test_busy_poll_cadence_uses_queued_start_even_across_restart(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        delay = self.tick(7)
        count = self.forge.paths("GET").count(JOBS)
        self.assertEqual(7, delay)
        delay = self.tick(delay)
        self.assertEqual(7, delay)
        delay = self.tick(delay)
        self.assertEqual(1, delay)
        self.assertEqual(count, self.forge.paths("GET").count(JOBS))
        self.tick(delay)
        self.assertEqual(count + 1, self.forge.paths("GET").count(JOBS))

        self.restart()
        self.tick(280 - self.clock.now)
        count = self.forge.paths("GET").count(JOBS)
        self.tick(14)
        self.assertEqual(count, self.forge.paths("GET").count(JOBS))
        self.tick(1)
        self.assertEqual(count + 1, self.forge.paths("GET").count(JOBS))

        self.restart()
        self.tick(5)
        count = self.forge.paths("GET").count(JOBS)
        self.assertEqual(2, self.tick(58))
        self.assertEqual(count, self.forge.paths("GET").count(JOBS))
        self.tick(2)
        self.assertEqual(count + 1, self.forge.paths("GET").count(JOBS))

    def test_unavailable_or_malformed_jobs_are_not_cancellation_evidence(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.forge.jobs = None
        self.tick(7)
        for endpoint, status, body in (
            (JOBS, 503, None),
            (JOBS, 200, b"{"),
            (JOBS, 200, [job(repo_id=None)]),
            (USER, 401, None),
        ):
            with self.subTest(endpoint=endpoint, status=status, body=body):
                self.forge.reply_once("GET", endpoint, status, body)
                self.tick(D.BUSY_POLL_FAST)
                self.tick(D.BUSY_POLL_FAST)
                self.assertEqual([], self.system.mutations("stop"))
        self.system.set()
        self.tick()
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assert_scrubbed()

    def test_uncertain_start_and_pending_jobs_block_cleanup_and_second_start(self):
        self.forge.jobs = [job(), job(2, "other")]
        self.system.start_mode = "uncertain"
        self.tick()
        queued_at = self.state()["active"]["queued_at"]
        self.restart()
        self.tick(7)  # ActiveState=inactive with a queued start is not idle.
        self.system.set(active="activating", pending="71")
        self.tick(7)
        self.system.set(active="active")
        self.tick(7)
        self.assertEqual(queued_at, self.state()["active"]["queued_at"])
        self.assertEqual(1, len(self.system.mutations("start")))
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertTrue(self.credential_dir.exists())

    def test_crash_after_queuing_start_is_adopted_without_another_start(self):
        self.forge.jobs = [job()]
        self.system.start_mode = "crash"
        with self.assertRaises(Crash):
            self.tick()
        self.restart()
        self.tick(7)
        self.assertEqual(1, len(self.system.mutations("start")))
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertTrue(self.credential_dir.exists())

    def test_failed_start_and_same_handle_dedup_across_restart(self):
        self.forge.jobs = [job()]
        self.system.start_mode = "failed"
        self.tick()
        self.assertTrue(self.credential_dir.exists())
        self.restart()
        self.tick(7)
        self.assert_scrubbed()
        self.assertIsNone(self.state()["active"])
        self.assertEqual([job()["handle"]], self.state()["retired"])
        self.restart()
        self.tick(7)
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assertEqual(1, len(self.system.mutations("start")))

    def test_leftover_support_units_stopped_before_scrub_and_delete(self):
        self.forge.jobs = [job()]
        self.tick()
        self.leave_images()
        self.system.set(pending="72")
        for unit in D.SUPPORT:
            self.system.set(unit, active="active")
        self.restart()
        self.tick(7)
        self.assertEqual([], self.system.mutations("stop"))
        self.system.set()
        self.tick(7)
        required = {
            "microvm-tap-interfaces@ryza-eph-1.service",
            "microvm-virtiofsd@ryza-eph-1.service",
            "microvm-set-booted@ryza-eph-1.service",
        }
        [stop] = self.system.mutations("stop")
        self.assertTrue(required.issubset(stop))
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertTrue(self.credential_dir.exists())
        for unit in D.SUPPORT:
            self.system.set(unit)
        self.tick(7)
        self.assert_scrubbed()
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))

    def test_recheck_vm_after_support_status_prevents_a_racy_stop_and_scrub(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set()
        self.system.set(D.SUPPORT[0], active="active")
        self.system.on_show = lambda unit: self.system.set(pending="73") if unit == D.SUPPORT[-1] else None
        self.tick(7)
        self.assertEqual([], self.system.mutations("stop"))
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertTrue(self.credential_dir.exists())

    def test_scrubs_exact_files_and_crashed_staging_but_refuses_unexpected_files(self):
        self.leave_images()
        declared = self.vm_dir / "current"
        declared.symlink_to("declaration")
        self.credential_dir.mkdir()
        unexpected = self.credential_dir / "do-not-delete"
        unexpected.touch()
        (self.credential_dir / "runner-token").write_text(TOKEN)
        self.files.staging.mkdir()
        (self.files.staging / "runner-token").write_text(TOKEN)
        sibling = self.credential_dir.with_name("other-vm")
        sibling.mkdir()
        self.tick()
        self.assertTrue(declared.is_symlink())
        self.assertTrue(unexpected.is_file())
        self.assertTrue(sibling.is_dir())
        self.assertFalse((self.credential_dir / "runner-token").exists())
        self.assertFalse(self.files.staging.exists())
        self.assertFalse((self.vm_dir / "var.img").exists())
        self.assertEqual([], self.forge.calls)

    def test_missing_host_pat_does_not_prevent_local_cleanup(self):
        self.forge.jobs = [job()]
        self.tick()
        self.leave_images()
        self.system.set()
        self.pat_file.unlink()
        self.restart()
        self.tick()
        self.assert_scrubbed()
        self.assertEqual("cleanup", self.state()["active"]["phase"])
        self.assertIn("forgejo-pat credential is unavailable", self.logs.getvalue())
        self.assertEqual([], self.forge.paths("DELETE"))
        self.pat_file.write_text(PAT)
        self.tick(7)
        self.assertIsNone(self.state()["active"])

    def test_malformed_registration_token_keeps_known_runner_for_cleanup(self):
        self.forge.jobs = [job()]
        runner_id = self.forge.add_runner("fake-known-runner")
        self.forge.reply_once("POST", RUNNERS, 201, {"uuid": uuid_for(runner_id), "id": runner_id})
        self.tick()
        self.assertEqual("registered", self.state()["active"]["phase"])
        self.assertEqual([], self.system.mutations())
        self.assert_scrubbed()
        self.tick(7)
        self.assertEqual([RUNNERS + f"/{runner_id}"], self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS], self.forge.paths("POST"))

    def test_crash_after_stage_before_start_intent_scrubs_without_booting(self):
        self.forge.jobs = [job()]
        store = self.dispatcher.store
        durable_save = store.save

        def crash_before_start(**changes):
            if changes.get("active", {}).get("phase") == "start":
                raise Crash
            durable_save(**changes)

        with patch.object(store, "save", side_effect=crash_before_start), self.assertRaises(Crash):
            self.tick()
        self.assertTrue(self.credential_dir.exists())
        self.assertEqual("registered", self.state()["active"]["phase"])
        self.restart()
        self.tick(7)
        self.assert_scrubbed()
        self.assertEqual([], self.system.mutations())
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))

    def test_crash_after_post_discovers_and_deletes_exact_owned_runner(self):
        self.forge.jobs = [job()]
        durable_save = self.dispatcher.store.save

        def crash_after_post(**changes):
            if changes.get("active", {}).get("phase") == "registered":
                raise Crash
            durable_save(**changes)

        with patch.object(self.dispatcher.store, "save", side_effect=crash_after_post), self.assertRaises(Crash):
            self.tick()
        original = self.state()["active"]
        self.assertEqual("intent", original["phase"])
        self.assertEqual(original["name"], self.forge.runners[100]["name"])
        self.restart()
        self.tick()
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertEqual([], self.system.mutations())
        self.assertEqual({}, self.state()["ambiguous"])

    def test_late_ambiguous_post_rescans_pages_and_deletes_only_exact_matches(self):
        self.forge.jobs = [job()]
        self.forge.reply_once("POST", RUNNERS, 502, {"secret_echo": TOKEN})
        self.tick()
        original = self.state()["active"]
        self.tick(D.INVENTORY_POLL)
        self.assertEqual({original["handle"]: {"name": original["name"], "runners": None}}, self.state()["ambiguous"])
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertEqual([], self.forge.paths("DELETE"))

        sink = FakeForge()
        self.addCleanup(sink.close)
        self.forge.page_size = 2
        self.forge.next_link = sink.url + "/must-not-forward-authorization"
        name = original["name"]
        self.forge.add_runner(name + "-not-exact")
        match1 = self.forge.add_runner(name)
        self.forge.add_runner(name, owner_id=OWNER + 1)
        self.forge.add_runner(name, ephemeral=False)
        self.forge.add_runner(name, repo_id=REPO)
        match2 = self.forge.add_runner(name)
        self.forge.jobs.append(job(2, "different-job"))
        self.tick(D.INVENTORY_POLL)
        self.assertEqual([], sink.calls)
        self.assertIn(LIST.format(2), self.forge.paths("GET"))
        self.assertIn(LIST.format(3), self.forge.paths("GET"))
        self.assertEqual([RUNNERS + f"/{match1}", RUNNERS + f"/{match2}"], self.forge.paths("DELETE"))
        self.assertEqual({}, self.state()["ambiguous"])
        self.assertEqual("different-job", self.state()["active"]["handle"])
        self.assertEqual(5, len(self.forge.runners))  # Four nonmatches plus the new allocation.

    def test_unresolved_empty_inventory_allows_other_handle_not_original(self):
        self.forge.jobs = [job(), job(2, "other")]
        with patch.object(self.dispatcher.api, "register", side_effect=Crash), self.assertRaises(Crash):
            self.tick()
        old_name = self.state()["active"]["name"]
        self.assertEqual([], self.forge.paths("POST"))
        self.restart()
        self.tick(7)
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertEqual("other", self.state()["active"]["handle"])
        self.assertEqual(old_name, self.state()["ambiguous"][job()["handle"]]["name"])

    def test_recovered_ids_are_durable_before_delete_and_replayed_on_404(self):
        self.forge.jobs = [job()]
        self.forge.reply_once("POST", RUNNERS, 403)
        self.tick()
        self.forge.reply_once("POST", RUNNERS, 201, b"{broken JSON " + TOKEN.encode())
        self.tick(7)
        entry = self.state()["active"]
        self.assertIn(entry["handle"], self.state()["refusals"])
        runner_id = self.forge.add_runner(entry["name"])
        with patch.object(self.dispatcher.api, "delete", side_effect=Crash), self.assertRaises(Crash):
            self.tick(D.INVENTORY_POLL)
        self.assertEqual(
            [{"id": runner_id, "uuid": uuid_for(runner_id)}], self.state()["ambiguous"][entry["handle"]]["runners"]
        )
        self.assertEqual({}, self.state()["refusals"])
        del self.forge.runners[runner_id]  # DELETE succeeded remotely, but the client never got the reply.
        self.restart()
        self.tick()
        self.assertEqual([RUNNERS + f"/{runner_id}"], self.forge.paths("DELETE"))
        self.assertIn("HTTP 404", self.logs.getvalue())
        self.assertEqual({}, self.state()["ambiguous"])
        self.assertEqual([RUNNERS, RUNNERS], self.forge.paths("POST"))

    def test_delete_errors_back_off_after_local_teardown_and_keep_slot_reserved(self):
        self.forge.jobs = [job(), job(2, "other")]
        self.tick()
        self.leave_images()
        self.system.set()
        endpoint = RUNNERS + "/100"
        for status in (401, 403, 429, 503):
            self.forge.reply_once("DELETE", endpoint, status, {"error": TOKEN})
        for index, (advance, status) in enumerate(((0, 401), (7, 403), (14, 429), (28, 503)), start=1):
            self.tick(advance)
            self.assertEqual([endpoint] * index, self.forge.paths("DELETE"))
            self.assertEqual("cleanup", self.state()["active"]["phase"])
            self.assertEqual([RUNNERS], self.forge.paths("POST"))
            self.assertIn(f"HTTP {status}", self.logs.getvalue())
            self.assert_scrubbed()
            self.tick(0)
            self.assertEqual([endpoint] * index, self.forge.paths("DELETE"))
        del self.forge.runners[100]  # Forgejo may auto-delete after a completed job.
        self.tick(56)
        self.assertEqual([endpoint] * 5, self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS, RUNNERS], self.forge.paths("POST"))
        self.assertEqual("other", self.state()["active"]["handle"])
        self.assertIn("HTTP 404", self.logs.getvalue())

    def test_account_change_blocks_old_id_cleanup_and_new_dispatch(self):
        self.forge.jobs = [job(), job(2, "other")]
        self.tick()
        self.system.set()
        self.forge.identity = {"login": "manjo", "id": OWNER + 1}
        self.tick()
        self.assert_scrubbed()
        self.assertEqual("cleanup", self.state()["active"]["phase"])
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertIn("account ID changed", self.logs.getvalue())
        self.forge.identity = {"login": "wrong-account", "id": OWNER}
        self.tick(7)
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertIn("not the expected manjo account", self.logs.getvalue())

    def test_timeout_is_ambiguous_and_does_not_repost(self):
        self.forge.jobs = [job()]
        release = threading.Event()
        self.forge.reply_once("POST", RUNNERS, 201, release)
        try:
            with patch.object(D, "REQUEST_TIMEOUT", 0.5):
                self.tick()
        finally:
            release.set()
        self.assertIn("connection failed or timed out", self.logs.getvalue())
        self.assertEqual("intent", self.state()["active"]["phase"])
        self.assertEqual({}, self.state()["refusals"])
        self.tick(7)
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertEqual([], self.system.mutations())
        self.assertIn(job()["handle"], self.state()["ambiguous"])

    def test_api_redirect_is_not_followed(self):
        sink = FakeForge()
        self.addCleanup(sink.close)
        self.forge.jobs = [job()]
        self.forge.reply_once("POST", RUNNERS, 307, {"message": PAT}, Location=sink.url + "/outside")
        self.tick()
        self.assertEqual([], sink.calls)
        self.assertIn("HTTP 307", self.logs.getvalue())
        self.assertEqual([], self.system.mutations())
        self.assertIsNone(self.state()["active"])
        self.assertEqual([], self.state()["retired"])
        self.assertEqual({}, self.state()["ambiguous"])
        self.assertEqual(1, self.state()["refusals"][job()["handle"]]["count"])

    def test_scope_recovery_resends_same_handle_after_restart(self):
        queued = job()
        self.forge.jobs = [queued]
        self.forge.reply_once("POST", RUNNERS, 403, {"error": TOKEN})
        self.tick()
        self.assertIn("register runner: HTTP 403", self.logs.getvalue())
        self.assertIsNone(self.state()["active"])
        self.assertEqual({}, self.state()["ambiguous"])
        self.assertEqual([], self.state()["retired"])
        self.assertEqual(1, self.state()["refusals"][queued["handle"]]["count"])
        self.restart()
        self.tick()
        self.assertEqual([RUNNERS, RUNNERS], self.forge.paths("POST"))
        self.assertEqual(queued["handle"], self.state()["active"]["handle"])
        self.assertEqual({}, self.state()["refusals"])
        self.assertEqual(1, self.forge.paths("GET").count(LIST.format(1)))

    def test_rate_limit_and_http_408_retry_with_global_backoff(self):
        queued = job()
        self.forge.jobs = [queued, job(2, "other")]
        self.forge.reply_once("POST", RUNNERS, 429)
        self.forge.reply_once("POST", RUNNERS, 408)
        for count, advance, delay in ((1, 0, 7), (2, 1, 14)):
            self.tick(advance)
            self.assertIsNone(self.state()["active"])
            self.assertEqual({}, self.state()["ambiguous"])
            self.assertEqual([], self.state()["retired"])
            self.assertEqual(count, self.state()["refusals"][queued["handle"]]["count"])
            paths = self.forge.paths()
            self.tick(delay - 1)
            self.assertEqual(paths, self.forge.paths())
        self.tick(1)
        self.assertEqual([RUNNERS] * 3, self.forge.paths("POST"))
        self.assertEqual(queued["handle"], self.state()["active"]["handle"])
        self.assertEqual({}, self.state()["refusals"])
        self.assertEqual(1, self.forge.paths("GET").count(LIST.format(1)))

    def test_refusal_budget_requires_three_refusals_even_after_an_hour(self):
        handle = job()["handle"]
        self.forge.jobs = [job()]
        for _ in range(3):
            self.forge.reply_once("POST", RUNNERS, 403)
        self.tick()
        self.restart()
        self.tick(3600)
        self.assertEqual([], self.state()["retired"])
        self.assertEqual(2, self.state()["refusals"][handle]["count"])
        self.restart()
        self.tick(7)
        self.assertEqual([handle], self.state()["retired"])
        self.assertEqual({}, self.state()["refusals"])

    def test_three_early_refusals_do_not_retire_handle_until_full_hour(self):
        handle = job()["handle"]
        self.forge.jobs = [job()]
        for _ in range(4):
            self.forge.reply_once("POST", RUNNERS, 429)
        self.tick()
        first_at = self.clock.wall()
        self.tick(7)
        self.restart()
        self.tick(3592)
        self.assertEqual([], self.state()["retired"])
        self.assertEqual({"count": 3, "first_at": first_at}, self.state()["refusals"][handle])
        self.restart()
        self.tick(1)
        self.assertEqual([handle], self.state()["retired"])
        self.assertIsNone(self.state()["active"])
        self.assertEqual({}, self.state()["refusals"])
        self.restart()
        self.tick()
        self.assertEqual([RUNNERS] * 4, self.forge.paths("POST"))
        self.assertEqual(1, self.forge.paths("GET").count(LIST.format(1)))

    def test_refusal_budget_is_per_handle_and_cleared_only_by_valid_absence(self):
        first, second = job(), job(2, "other")
        self.forge.jobs = [first, second]
        self.forge.reply_once("POST", RUNNERS, 403)
        self.tick()
        self.forge.jobs = [first | {"status": "running", "task_id": 71}, second]
        self.forge.reply_once("POST", RUNNERS, 429)
        self.tick(7)
        budget = self.state()["refusals"]
        self.assertEqual({first["handle"], second["handle"]}, budget.keys())
        self.assertEqual([1, 1], [item["count"] for item in budget.values()])

        self.pause.touch()
        self.forge.jobs = [second]
        self.forge.reply_once("GET", JOBS, 200, {"invalid": True})
        self.tick(14)
        self.assertEqual(budget, self.state()["refusals"])
        self.tick(28)
        self.assertEqual({second["handle"]: budget[second["handle"]]}, self.state()["refusals"])
        self.assertEqual([RUNNERS, RUNNERS], self.forge.paths("POST"))

        self.restart()
        self.pause.unlink()
        self.forge.jobs = [first, second]
        self.forge.reply_once("POST", RUNNERS, 403)
        self.tick(3600)
        self.assertEqual({"count": 1, "first_at": self.clock.wall()}, self.state()["refusals"][first["handle"]])
        self.assertEqual(budget[second["handle"]], self.state()["refusals"][second["handle"]])
        self.assertEqual([], self.state()["retired"])

    def test_inventory_is_throttled_and_never_runs_while_busy(self):
        original = job()
        self.forge.jobs = [original, job(2, "other")]
        self.forge.reply_once("POST", RUNNERS, 502)
        self.tick()
        self.tick(7)
        self.assertEqual("other", self.state()["active"]["handle"])
        intent = self.state()["ambiguous"][original["handle"]]
        later = self.forge.add_runner(intent["name"])
        self.system.set(active="active")
        self.tick(D.INVENTORY_POLL)
        self.tick(D.BUSY_POLL)
        self.assertEqual(1, self.forge.paths("GET").count(LIST.format(1)))
        self.assertEqual([], self.forge.paths("DELETE"))
        self.pause.touch()
        self.system.set()
        self.tick(7)
        self.assertEqual([RUNNERS + "/100", RUNNERS + f"/{later}"], self.forge.paths("DELETE"))
        self.assertEqual(2, self.forge.paths("GET").count(LIST.format(1)))
        self.assertEqual({}, self.state()["ambiguous"])
        self.assertIsNone(self.state()["active"])
        self.assert_scrubbed()

    def test_absent_handle_expiry_is_durable_and_reappearance_resets_it(self):
        handle = job()["handle"]
        self.forge.jobs = [job()]
        self.forge.reply_once("POST", RUNNERS, 502)
        self.tick()
        self.forge.jobs = None
        self.tick(D.INVENTORY_POLL)
        started = self.state()["ambiguous"][handle]["absent_since"]
        self.assertEqual(self.clock.wall(), started)
        self.restart()
        self.tick(D.INTENT_EXPIRY // 2)
        self.assertEqual(started, self.state()["ambiguous"][handle]["absent_since"])
        self.forge.jobs = [job()]
        self.tick(D.POLL)
        self.assertNotIn("absent_since", self.state()["ambiguous"][handle])
        self.forge.jobs = None
        self.tick(D.POLL)
        self.assertNotIn("absent_since", self.state()["ambiguous"][handle])
        self.tick(D.INVENTORY_POLL - 2 * D.POLL)
        self.assertEqual(self.clock.wall(), self.state()["ambiguous"][handle]["absent_since"])
        self.restart()
        self.tick(D.INTENT_EXPIRY - 1)
        self.assertIn(handle, self.state()["ambiguous"])
        self.restart()
        self.tick(1)
        self.assertEqual({}, self.state()["ambiguous"])
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertIn("expired registration intent", self.logs.getvalue())

    def test_expiry_requires_complete_successful_inventories_and_jobs(self):
        handle = job()["handle"]
        self.forge.jobs = [job()]
        self.forge.reply_once("POST", RUNNERS, 502)
        self.tick()
        self.forge.jobs = None
        self.forge.reply_once("GET", LIST.format(1), 502)
        self.tick(D.INVENTORY_POLL)
        self.assertNotIn("absent_since", self.state()["ambiguous"][handle])
        for _ in range(5):
            self.tick(D.POLL)
        self.assertEqual(2, self.forge.paths("GET").count(LIST.format(1)))
        self.assertEqual(0, self.logs.getvalue().count("unresolved registration(s)"))
        self.tick(D.INVENTORY_POLL - 5 * D.POLL)
        self.assertEqual(self.clock.wall(), self.state()["ambiguous"][handle]["absent_since"])
        self.forge.reply_once(
            "GET", LIST.format(1), 200, [], **{"X-Total-Count": "1", "Link": '<ignored>; rel="next"'}
        )
        self.tick(D.INTENT_EXPIRY)
        self.assertIn(handle, self.state()["ambiguous"])
        self.forge.reply_once("GET", JOBS, 503)
        self.tick(D.INVENTORY_POLL)
        self.assertIn(handle, self.state()["ambiguous"])
        self.tick(D.POLL)
        self.assertIn(handle, self.state()["ambiguous"])
        self.tick(D.INVENTORY_POLL - D.POLL)
        self.assertEqual({}, self.state()["ambiguous"])

    def test_pause_persists_across_restart_and_does_not_block_known_cleanup(self):
        self.forge.jobs = [job(), job(2, "other")]
        self.pause.touch()
        self.tick()
        self.tick(7)
        identity_message = "Forgejo PAT identity verified as manjo"
        self.assertEqual(1, self.logs.getvalue().count(identity_message))
        self.assertEqual([], self.forge.paths("POST"))
        self.pause.unlink()
        self.tick(7)
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.leave_images()
        self.pause.touch()
        self.system.set(active="active")
        self.tick(7)
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.system.set()
        self.restart()
        self.tick(7)
        self.assertEqual(2, self.logs.getvalue().count(identity_message))
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertIsNone(self.state()["active"])
        self.assert_scrubbed()
        self.pause.unlink()
        self.tick(7)
        self.assertEqual([RUNNERS, RUNNERS], self.forge.paths("POST"))
        self.assertEqual("other", self.state()["active"]["handle"])

    def test_unknown_systemd_states_and_unowned_vm_fail_closed(self):
        self.forge.jobs = [job()]
        self.leave_images()
        for attributes in ({"loaded": "not-found"}, {"pending": "unknown"}, {"active": "maintenance"}, {"active": "active"}):
            with self.subTest(attributes=attributes):
                self.system.set(**attributes)
                self.tick(7)
                self.assertEqual([], self.forge.calls)
                self.assertEqual([], self.system.mutations())
                self.assertTrue((self.vm_dir / "var.img").exists())

    def test_lost_state_with_named_runner_and_invalid_state_fail_closed(self):
        runner_id = self.forge.add_runner("eph-0123456789ab-ryza-0123456789abcdef0123456789abcdef")
        self.forge.jobs = [job()]
        self.tick()
        self.assertIn(runner_id, self.forge.runners)
        self.assertIn("state.json absent", self.logs.getvalue())
        self.assertEqual([], self.forge.paths("POST"))
        self.assertEqual([], self.forge.paths("DELETE"))
        (self.state_dir / "state.json").write_text('{"version":999}')
        with self.assertRaises(D.StateError):
            self.restart()

    def test_invalid_current_state_fields_fail_closed(self):
        self.forge.jobs = [job()]
        self.tick()
        data = self.state()
        for invalid in (
            data | {"active": data["active"] | {"assigned": True}},
            data | {"active": data["active"] | {"queued_at": None}},
            data | {"refusals": {job()["handle"]: {"count": True, "first_at": self.clock.wall()}}},
            data | {"refusals": {job()["handle"]: {"count": 1, "first_at": float("nan")}}},
        ):
            with self.subTest(invalid=invalid):
                (self.state_dir / "state.json").write_text(json.dumps(invalid))
                with self.assertRaises(D.StateError):
                    self.restart()


class TrustedJobTests(unittest.TestCase):
    """HOM-31: every slot boots untrusted; CI upload credentials only follow an exact, trusted run."""

    def setUp(self):
        self.surfaces = []
        self.build()

    def build(self, trusted=True):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.state_dir, self.vm_dir = root / "state", root / "vm"
        self.credential_dir = root / "credentials" / "ryza-eph-1"
        self.trust_dir = root / "credentials" / "ryza-eph-1-trust"
        self.sources = root / "sources"
        for directory in (self.state_dir, self.vm_dir, self.credential_dir.parent, self.sources):
            directory.mkdir(mode=0o700)
        (self.sources / "trusted-ci-signing-key").write_bytes(SIGNING_KEY)
        (self.sources / "trusted-ncps-netrc").write_bytes(NETRC)
        self.pat_file = root / "forgejo-pat"
        self.pat_file.write_text(PAT)
        self.pause = root / "pause"
        self.forge = FakeForge()
        self.addCleanup(self.forge.close)
        self.forge.tasks = [task(70, 6), task()]
        self.forge.runs = [run(6, commit_sha="old"), run()]
        self.system = FakeSystemctl()
        self.files = D.SlotFiles(
            self.vm_dir, self.credential_dir, os.getuid(), os.getgid(), self.trust_dir if trusted else None
        )
        self.clock = FakeClock()
        self.logs = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.logs))
        self.surfaces.append((self.logs, self.system, self.state_dir))
        self.trusted = trusted
        self.restart()

    def tearDown(self):
        for logs, system, state_dir in self.surfaces:
            surface = logs.getvalue() + repr(system.calls)
            for state_file in state_dir.glob("state.json*"):
                surface += state_file.read_text()
            for secret in (PAT, TOKEN, SIGNING_SECRET, NETRC_PASSWORD):
                self.assertNotIn(secret, surface)

    def restart(self):
        self.dispatcher = D.Dispatcher(
            REPO,
            D.Forgejo(self.pat_file, self.forge.connect),
            D.Systemctl(self.system.run),
            self.files,
            D.Store(self.state_dir),
            self.clock.monotonic,
            self.clock.wall,
            pause=self.pause,
            trust=D.Trust(REPO_NAME, self.sources) if self.trusted else None,
        )

    def tick(self, advance=0):
        self.clock.now += advance
        return self.dispatcher.tick()

    def boot(self):
        """Dispatch job 1 and let the VM come up with the job still unassigned."""
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")

    def pick_up(self, task_id=71, advance=D.POLL):
        self.forge.jobs = [job(status="running", task_id=task_id)]
        return self.tick(advance)

    def delivered(self):
        return {path.name: path.read_bytes() for path in self.trust_dir.iterdir()} if self.trust_dir.exists() else None

    def polls(self):
        return self.forge.paths("GET").count(JOBS)

    def assert_settled_cadence(self):
        self.tick(D.POLL)  # The poll scheduled while resolving; it picks the normal busy interval.
        polls = self.polls()
        self.tick(D.POLL)
        self.assertEqual(polls, self.polls())

    def lookups(self):
        return [path for path in self.forge.paths("GET") if path.startswith(REPOSITORY)]

    def test_boots_untrusted_and_delivers_after_exact_trusted_pickup(self):
        self.boot()
        self.assertEqual({}, self.delivered())
        self.assertEqual(0o700, stat.S_IMODE(self.trust_dir.stat().st_mode))
        self.assertEqual({"runner-uuid", "runner-token", "job-handle"}, {p.name for p in self.credential_dir.iterdir()})
        polls = self.polls()
        self.tick(D.POLL)  # Not picked up yet: fast polls, no repository lookups.
        self.assertEqual(polls + 1, self.polls())
        self.assertEqual([], self.lookups())
        polls = self.forge.paths("GET").count(JOBS)
        self.pick_up()
        self.assertEqual({"ncps-netrc": NETRC, "ci-signing-key": SIGNING_KEY}, self.delivered())
        for path in self.trust_dir.iterdir():
            info = path.stat()
            self.assertEqual((0o400, os.getuid()), (stat.S_IMODE(info.st_mode), info.st_uid))
        self.assertEqual([REPOSITORY, TASKS.format(1), RUN.format(7), RUN.format(7)], self.lookups())
        self.assertEqual(polls + 2, self.forge.paths("GET").count(JOBS))  # The poll plus the pre-delivery recheck.
        self.assertIn("trusted: run #7 (push); delivered CI upload credentials", self.logs.getvalue())
        self.assert_settled_cadence()
        self.assertEqual(4, len(self.lookups()))
        self.assertEqual([], self.system.mutations("stop"))
        self.system.set()
        self.tick(D.POLL)
        self.assertFalse(self.trust_dir.exists())
        self.assertFalse(self.credential_dir.exists())

    def test_trusted_schedules_and_manual_dispatches(self):
        for fields in (
            {"trigger_event": "schedule", "ScheduleID": 3, "trigger_user": {"id": D.ACTIONS_USER}},
            {"event": "schedule", "trigger_event": "schedule", "ScheduleID": 3, "trigger_user": {"id": -2}},
            {"event": "workflow_dispatch", "trigger_event": "workflow_dispatch", "prettyref": "release"},
        ):
            with self.subTest(fields=fields):
                self.build()
                self.forge.runs = [run(**fields)]
                self.boot()
                self.pick_up()
                self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))

    def test_untrusted_runs_get_nothing_and_keep_running(self):
        fork = {"is_fork_pull_request": True, "event": "pull_request", "trigger_event": "pull_request"}
        for reason, fields in (
            ("fork or AGit pull request", fork | {"trigger_user": {"id": HERMES}}),
            ("fork or AGit pull request", fork | {"trigger_user": {"id": OWNER}}),  # AGit by manjo is still a fork.
            ("fork or AGit pull request", fork | {"trigger_user": {"id": HERMES}, "approved_by": OWNER}),
            ("awaiting approval", {"need_approval": True}),
            ("push not by manjo", {"trigger_user": {"id": HERMES}}),
            ("event is not push", {"event": "pull_request", "trigger_event": "pull_request"}),
            ("event is not push", {"event": "pull_request", "trigger_event": "pull_request_target"}),
            ("event is not push", {"event": "issue_comment", "trigger_event": "issue_comment"}),
            ("dispatch on a pull request ref", {"event": "workflow_dispatch", "trigger_event": "workflow_dispatch", "prettyref": "#12"}),
            ("dispatch not by manjo", {"event": "workflow_dispatch", "trigger_event": "workflow_dispatch", "trigger_user": {"id": HERMES}}),
            ("push run carries a schedule", {"ScheduleID": 4}),
            ("schedule run without a schedule", {"trigger_event": "schedule", "trigger_user": {"id": -2}}),
            ("schedule not triggered by forgejo-actions", {"trigger_event": "schedule", "ScheduleID": 4}),
            ("repository mismatch", {"repository": {"id": REPO + 1, "owner": {"id": OWNER, "login": "manjo"}}}),
            ("repository mismatch", {"repository": {"id": REPO, "owner": {"id": OWNER, "login": "hermes"}}}),
            ("invalid run metadata", {"is_fork_pull_request": None}),
            ("invalid run metadata", {"ScheduleID": "0"}),
            ("invalid run metadata", {"trigger_user": None}),
            ("task and run disagree", {"commit_sha": "other"}),
            ("task and run disagree", {"workflow_id": "other.yml"}),
        ):
            with self.subTest(reason=reason, fields=fields):
                self.build()
                self.forge.runs = [run(**fields)]
                self.boot()
                self.pick_up()
                self.assertEqual({}, self.delivered())
                self.assertIn(f"untrusted: run #7 ({reason}", self.logs.getvalue())
                lookups = len(self.lookups())
                self.tick(D.BUSY_POLL_FAST)
                self.assertEqual(lookups, len(self.lookups()))
                self.assertEqual([], self.system.mutations("stop"))

    def test_missing_fields_are_untrusted(self):
        for missing in ("ScheduleID", "event", "trigger_event", "need_approval", "prettyref", "repository"):
            with self.subTest(missing=missing):
                self.build()
                entry = run()
                del entry[missing]
                self.forge.runs = [entry]
                self.boot()
                self.pick_up()
                self.assertEqual({}, self.delivered())
                self.assertIn("untrusted: run #7 (invalid run metadata)", self.logs.getvalue())

    def test_lookup_failures_withhold_then_give_up_at_deadline(self):
        for endpoint, status, body in (
            (REPOSITORY, 403, {"message": PAT}),
            (TASKS.format(1), 500, None),
            (TASKS.format(1), 200, {"total_count": 0, "workflow_runs": []}),
            (TASKS.format(1), 200, b"{" + TOKEN.encode()),
            (TASKS.format(1), 200, {"total_count": 1, "workflow_runs": [task(run_number="7")]}),
            (RUN.format(7), 200, {"total_count": 2, "workflow_runs": [run(), run()]}),
            (RUN.format(7), 200, {"total_count": 1, "workflow_runs": [run(8)]}),
            (RUN.format(7), 404, None),
        ):
            with self.subTest(endpoint=endpoint, status=status):
                self.build()
                self.boot()
                for _ in range(200):
                    self.forge.reply_once("GET", endpoint, status, body)
                self.pick_up()
                self.assertEqual({}, self.delivered())
                self.assertIn("trust lookup pending", self.logs.getvalue())
                if status == 403:
                    self.assertIn("read:repository", self.logs.getvalue())
                polls = self.polls()
                self.tick(D.POLL)  # Pending: keep polling fast.
                self.assertEqual(polls + 1, self.polls())
                self.tick(D.TRUST_DEADLINE - 2 * D.POLL)
                self.assertNotIn("gave up", self.logs.getvalue())
                self.tick(D.POLL)
                self.assertIn("untrusted: trust lookup gave up after 10 min", self.logs.getvalue())
                self.assert_settled_cadence()
                self.assertEqual({}, self.delivered())
                lookups = len(self.lookups())
                self.forge.faults.clear()
                self.tick(D.BUSY_POLL)
                self.assertEqual(lookups, len(self.lookups()))
                self.assertEqual([], self.system.mutations("stop"))

    def test_recovers_from_a_transient_lookup_error_before_the_deadline(self):
        self.boot()
        self.forge.reply_once("GET", TASKS.format(1), 503)
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.tick(D.POLL)
        self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))

    def test_task_lookup_pages_and_stops_at_older_tasks(self):
        self.forge.tasks = [task(1000 + n, 900 + n) for n in range(60)] + [task()]
        self.forge.runs = [run()]
        self.boot()
        self.pick_up()
        self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))
        self.assertIn(TASKS.format(2), self.lookups())
        self.build()
        self.forge.tasks = [task(10)]
        self.boot()
        self.pick_up()
        self.assertEqual([REPOSITORY, TASKS.format(1)], self.lookups())
        self.assertIn("job's task is not listed", self.logs.getvalue())

    def test_recheck_catches_a_changed_job_or_run_before_delivery(self):
        self.boot()
        self.forge.reply_once("GET", JOBS, 200, [job(status="running", task_id=71)])
        self.forge.reply_once("GET", JOBS, 200, [job(status="running", task_id=72)])
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.assertIn("job changed before delivery", self.logs.getvalue())

        self.build()
        self.boot()
        self.forge.reply_once("GET", RUN.format(7), 200, {"total_count": 1, "workflow_runs": [run()]})
        self.forge.reply_once(
            "GET", RUN.format(7), 200, {"total_count": 1, "workflow_runs": [run(is_fork_pull_request=True)]}
        )
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.assertIn("untrusted: run #7 (fork or AGit pull request)", self.logs.getvalue())

        self.build()
        self.boot()
        self.forge.reply_once("GET", RUN.format(7), 200, {"total_count": 1, "workflow_runs": [run()]})
        self.forge.reply_once("GET", RUN.format(7), 200, {"total_count": 1, "workflow_runs": [run(id=999)]})
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.assertIn("run changed before delivery", self.logs.getvalue())

    def test_job_finishing_before_pickup_is_seen_delivers_nothing(self):
        self.boot()
        self.forge.jobs = [job()]
        self.tick(D.POLL)
        self.system.set()
        self.tick(D.POLL)
        self.assertFalse(self.trust_dir.exists())
        self.assertEqual([], self.lookups())

    def test_bad_credential_sources_withhold(self):
        for name, value in (
            ("trusted-ci-signing-key", b""),
            ("trusted-ci-signing-key", b"no-colon-here"),
            ("trusted-ncps-netrc", b"machine evil.example\nlogin x\npassword y\n"),
            ("trusted-ncps-netrc", None),
        ):
            with self.subTest(name=name, value=value):
                self.build()
                if value is None:
                    (self.sources / name).unlink()
                else:
                    (self.sources / name).write_bytes(value)
                self.boot()
                self.pick_up()
                self.assertEqual({}, self.delivered())
                self.assertIn("credential missing or malformed; withheld", self.logs.getvalue())

    def test_restart_withdraws_and_re_resolves(self):
        self.boot()
        self.pick_up()
        self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))
        self.files.withdraw()  # What main() does before a new dispatcher runs.
        self.assertEqual({}, self.delivered())
        self.restart()
        self.tick(D.POLL)
        self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))
        self.forge.runs = [run(is_fork_pull_request=True)]
        self.files.withdraw()
        self.restart()
        self.tick(D.POLL)
        self.assertEqual({}, self.delivered())

    def test_trust_dir_is_fresh_for_every_boot(self):
        self.trust_dir.mkdir()
        (self.trust_dir / "ci-signing-key").write_bytes(SIGNING_KEY)
        (self.trust_dir / ".ncps-netrc.tmp").write_bytes(NETRC)
        self.boot()
        self.assertEqual({}, self.delivered())
        self.build()
        self.trust_dir.mkdir()
        (self.trust_dir / "unexpected").touch()
        self.forge.jobs = [job()]
        self.tick()
        self.assertIn("cannot scrub", self.logs.getvalue())
        self.assertEqual([], self.forge.paths("POST"))
        self.assertEqual([], self.system.mutations())

    def test_delivery_refuses_a_trust_dir_with_the_wrong_mode(self):
        self.boot()
        self.trust_dir.chmod(0o755)
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.assertIn("unexpected ownership or mode", self.logs.getvalue())

    def test_stopped_slot_gets_nothing_even_if_trusted(self):
        self.boot()
        self.system.on_show = lambda unit: self.system.set() if self.lookups() else None
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.tick(D.POLL)
        self.assertIsNone(self.delivered())  # Scrubbed by the local pass, never written.

    def test_gate_off_never_looks_up_or_delivers(self):
        self.build(trusted=False)
        self.boot()
        self.pick_up()
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual([], self.lookups())
        self.assertFalse(self.trust_dir.exists())


if __name__ == "__main__":
    unittest.main()
