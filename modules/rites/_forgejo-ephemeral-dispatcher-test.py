#!/usr/bin/env python3
"""Loopback Forgejo contract and fixed-slot lifecycle tests (no real credentials or units).

The dispatcher reaches the fake systemctl through its real transport: CommandSlot builds slotctl's argv and
stdin, slotctl's CLI (run in this process by InProcessSlotctl) parses them and acts on real temporary files.
SlotctlProcessTests also run slotctl as a real child process.
"""

import base64
import contextlib
import grp
import http.client
import importlib.util
import io
import json
import os
import pwd
import stat
import subprocess
import sys
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
SLOTCTL = Path(__file__).with_name("_forgejo-slotctl.py")
spec = importlib.util.spec_from_file_location("slotctl", SLOTCTL)
S = importlib.util.module_from_spec(spec)
spec.loader.exec_module(S)

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
TASKS = REPOSITORY + "/actions/tasks?status=running&page={}&limit=50"
KEYS = REPOSITORY + "/keys?page={}&limit=50"
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
        "repository": {"id": REPO, "name": REPO_NAME, "default_branch": "master", "owner": {"id": OWNER, "login": "manjo"}},
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


def write_slotctl_config(path, slot, vm_dir, credential_dir, trust_dir=None, deliver=False):
    """What the slot module generates per host, pointed at temporary directories and the current user."""
    entry = {
        "vm_dir": str(vm_dir),
        "credential_dir": str(credential_dir),
        "trust_dir": str(trust_dir or credential_dir.with_name(f"{credential_dir.name}-trust")),
        "deliver": deliver,
        "user": pwd.getpwuid(os.getuid()).pw_name,
        "group": grp.getgrgid(os.getgid()).gr_name,
    }
    path.write_text(json.dumps({"slots": {slot: entry}}))
    return path


class InProcessSlotctl:
    """subprocess.run for CommandSlot: runs slotctl's CLI here, against the fake systemctl, without a fork.

    The config path goes to slotctl the way the build compiles it in, never through argv.
    """

    def __init__(self, systemctl_run, config):
        self.systemctl_run, self.config = systemctl_run, str(config)
        self.calls = []

    def __call__(self, argv, *, input, stdout, stderr, pass_fds, timeout, check):
        assert stdout == subprocess.PIPE and stderr == subprocess.PIPE and not check and timeout > 0
        assert argv[0] == "slotctl" and isinstance(input, bytes)
        self.calls.append(tuple(argv))
        out, err = io.BytesIO(), io.StringIO()
        code = S.main(
            list(argv[1:]), stdin=io.BytesIO(input), stdout=out, stderr=err, run=self.systemctl_run, config=self.config
        )
        return subprocess.CompletedProcess(argv, code, out.getvalue(), err.getvalue().encode())


def command_slot(config, systemctl_run):
    slotctl = InProcessSlotctl(systemctl_run, config)
    return D.CommandSlot(("slotctl",), slotctl), slotctl


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
        self.keys = [{"id": 3, "title": "read-only mirror", "read_only": True}]

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
            if query.get("limit") != ["50"] or query.get("status") != ["running"]:
                return 400, {"error": "unexpected task query"}, {}
            page = int(query["page"][0])
            rows = sorted((row for row in self.tasks if row["status"] == "running"), key=lambda row: -row["id"])
            return 200, {"total_count": len(rows), "workflow_runs": rows[(page - 1) * 50 : page * 50]}, {}
        if method == "GET" and path.startswith(REPOSITORY + "/keys?"):
            query = parse_qs(urlsplit(path).query)
            if query.get("limit") != ["50"]:
                return 400, {"error": "unexpected key query"}, {}
            page = int(query["page"][0])
            return 200, self.keys[(page - 1) * 50 : page * 50], {"X-Total-Count": str(len(self.keys))}
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
        # For assertions on the slot's paths; the dispatcher itself goes through slotctl.
        self.files = S.SlotFiles(
            self.vm_dir, self.credential_dir, os.getuid(), os.getgid(), self.credential_dir.with_name("ryza-eph-1-trust"), False
        )
        self.config = write_slotctl_config(root / "slotctl.json", "ryza-eph-1", self.vm_dir, self.credential_dir)
        self.clock = FakeClock()
        self.logs = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.logs))
        self.restart()

    def tearDown(self):
        surface = self.logs.getvalue() + repr(self.system.calls) + repr(self.slotctl.calls)
        for state_file in self.state_dir.glob("state.json*"):
            surface += state_file.read_text()
        self.assertFalse(PAT in surface or TOKEN in surface, "credential found outside the HTTP header or slot staging")

    def restart(self):
        slot, self.slotctl = command_slot(self.config, self.system.run)
        self.dispatcher = D.Dispatcher(
            REPO,
            D.Forgejo(self.pat_file, self.forge.connect),
            slot,
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
        self.assertIn(f"reset {VM} after its cancellation stop timed out", self.logs.getvalue())
        self.assertNotIn("left failed", self.logs.getvalue())
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

    def cancel_until_stop(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="activating", pending="71")
        self.leave_images()
        self.tick(7)
        self.forge.jobs = None
        self.tick(D.BUSY_POLL_FAST)
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual(1, len(self.system.mutations("stop")))

    def test_reset_failed_error_is_logged_and_retried_without_blocking_cleanup(self):
        self.cancel_until_stop()
        self.system.set(active="failed", result="timeout")
        self.system.reset_fails = 1
        self.tick(7)
        self.assert_scrubbed()
        self.assertIn("systemctl reset-failed failed or timed out", self.logs.getvalue())
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.tick(7)
        self.assertEqual(2, len(self.system.mutations("reset-failed")))
        self.assertIn(f"reset {VM} after its cancellation stop timed out", self.logs.getvalue())
        self.tick(7)
        self.assertEqual(2, len(self.system.mutations("reset-failed")))

    def test_failures_other_than_our_stop_timing_out_are_left_failed(self):
        for result, cancelled in (("exit-code", False), ("timeout", False), ("signal", True), ("exit-code", True)):
            with self.subTest(result=result, cancelled=cancelled):
                self.setUp()
                if cancelled:
                    self.cancel_until_stop()
                else:
                    self.forge.jobs = [job()]
                    self.tick()
                    self.leave_images()
                self.system.set(active="failed", result=result)
                for _ in range(3):
                    self.tick(7)
                self.assert_scrubbed()
                self.assertEqual([], self.system.mutations("reset-failed"))
                self.assertEqual(1, self.logs.getvalue().count(f"slot ended {result}; left failed for inspection"))
                self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))

    def test_timeout_after_a_dispatcher_restart_is_left_failed(self):
        self.cancel_until_stop()
        self.restart()  # stop_queued is in memory only: the restarted dispatcher can't vouch for the timeout.
        self.system.set(active="failed", result="timeout")
        self.tick(7)
        self.assertEqual([], self.system.mutations("reset-failed"))
        self.assertIn("slot ended timeout; left failed for inspection", self.logs.getvalue())

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
        self.files = S.SlotFiles(self.vm_dir, self.credential_dir, os.getuid(), os.getgid(), self.trust_dir, trusted)
        self.config = write_slotctl_config(
            root / "slotctl.json", "ryza-eph-1", self.vm_dir, self.credential_dir, self.trust_dir, deliver=trusted
        )
        self.slotctls = []
        self.clock = FakeClock()
        self.logs = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.logs))
        self.surfaces.append((self.logs, self.system, self.state_dir, self.slotctls))
        self.trusted = trusted
        self.restart()

    def tearDown(self):
        for logs, system, state_dir, slotctls in self.surfaces:
            surface = logs.getvalue() + repr(system.calls) + repr([slotctl.calls for slotctl in slotctls])
            for state_file in state_dir.glob("state.json*"):
                surface += state_file.read_text()
            for secret in (PAT, TOKEN, SIGNING_SECRET, NETRC_PASSWORD):
                self.assertNotIn(secret, surface)

    def restart(self):
        slot, slotctl = command_slot(self.config, self.system.run)
        self.slotctls.append(slotctl)
        self.dispatcher = D.Dispatcher(
            REPO,
            D.Forgejo(self.pat_file, self.forge.connect),
            slot,
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
        self.tick(D.POLL)  # Not picked up yet: fast polls; only the up-front repository check so far.
        self.assertEqual(polls + 1, self.polls())
        self.assertEqual([REPOSITORY], self.lookups())
        self.assertIn("repository manjo/rust-app-template verified as ID 17", self.logs.getvalue())
        polls = self.forge.paths("GET").count(JOBS)
        self.pick_up()
        self.assertEqual({"ncps-netrc": NETRC, "ci-signing-key": SIGNING_KEY}, self.delivered())
        for path in self.trust_dir.iterdir():
            info = path.stat()
            self.assertEqual((0o400, os.getuid()), (stat.S_IMODE(info.st_mode), info.st_uid))
        self.assertEqual([REPOSITORY, TASKS.format(1), RUN.format(7), KEYS.format(1), RUN.format(7)], self.lookups())
        self.assertEqual(polls + 2, self.forge.paths("GET").count(JOBS))  # The poll plus the pre-delivery recheck.
        self.assertIn("trusted: run #7 (push); delivered CI upload credentials", self.logs.getvalue())
        self.assert_settled_cadence()
        self.assertEqual(5, len(self.lookups()))
        self.assertEqual([], self.system.mutations("stop"))
        self.system.set()
        self.tick(D.POLL)
        self.assertFalse(self.trust_dir.exists())
        self.assertFalse(self.credential_dir.exists())

    def test_trusted_schedules_and_manual_dispatches(self):
        for fields in (
            {"trigger_event": "schedule", "ScheduleID": 3, "trigger_user": {"id": D.ACTIONS_USER}},
            {"event": "schedule", "trigger_event": "schedule", "ScheduleID": 3, "trigger_user": {"id": -2}},
            {"event": "workflow_dispatch", "trigger_event": "workflow_dispatch", "prettyref": "master"},
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
            *(
                ("dispatch not on the default branch", {"event": "workflow_dispatch", "trigger_event": "workflow_dispatch", "prettyref": ref})
                for ref in ("pull/5/head", "#12", "0123456789abcdef0123456789abcdef01234567", "v1.0", "feature", "Master")
            ),
            ("push not on the default branch", {"prettyref": "feature"}),
            ("push not on the default branch", {"prettyref": "v1.0"}),
            ("schedule not on the default branch", {"trigger_event": "schedule", "ScheduleID": 4, "trigger_user": {"id": -2}, "prettyref": "old"}),
            ("invalid run metadata", {"repository": {"id": REPO, "default_branch": "", "owner": {"id": OWNER, "login": "manjo"}}}),
            ("invalid run metadata", {"repository": {"id": REPO, "default_branch": None, "owner": {"id": OWNER, "login": "manjo"}}}),
            ("invalid run metadata", {"prettyref": ""}),
            ("dispatch not by manjo", {"event": "workflow_dispatch", "trigger_event": "workflow_dispatch", "trigger_user": {"id": HERMES}}),
            ("push run carries a schedule", {"ScheduleID": 4}),
            ("schedule run without a schedule", {"trigger_event": "schedule", "trigger_user": {"id": -2}}),
            ("schedule not triggered by forgejo-actions", {"trigger_event": "schedule", "ScheduleID": 4}),
            ("repository mismatch", {"repository": {"id": REPO + 1, "default_branch": "master", "owner": {"id": OWNER, "login": "manjo"}}}),
            ("repository mismatch", {"repository": {"id": REPO, "default_branch": "master", "owner": {"id": OWNER, "login": "hermes"}}}),
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
            (KEYS.format(1), 403, None),
            (KEYS.format(1), 200, [{"id": 3, "read_only": True}]),  # No X-Total-Count.
            (KEYS.format(1), 200, {"keys": []}),
        ):
            with self.subTest(endpoint=endpoint, status=status):
                self.build()
                for _ in range(200):
                    self.forge.reply_once("GET", endpoint, status, body)
                self.boot()
                self.pick_up()
                self.assertEqual({}, self.delivered())
                self.assertIn("trust lookup pending", self.logs.getvalue())
                if status == 403:
                    self.assertIn("read:repository", self.logs.getvalue())
                if endpoint == REPOSITORY:
                    self.assertIn("cannot verify the trusted-job repository", self.logs.getvalue())
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
        self.assertEqual([REPOSITORY], self.lookups())

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
        self.dispatcher.slot.withdraw()  # What main() does before a new dispatcher runs.
        self.assertEqual({}, self.delivered())
        self.restart()
        self.tick(D.POLL)
        self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))
        self.forge.runs = [run(is_fork_pull_request=True)]
        self.dispatcher.slot.withdraw()
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
        self.system.on_show = lambda unit: self.system.set() if TASKS.format(1) in self.lookups() else None
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.tick(D.POLL)
        self.assertIsNone(self.delivered())  # Scrubbed by the local pass, never written.

    def test_write_deploy_keys_disable_trust(self):
        for keys in (
            [{"id": 3, "read_only": False}],
            [{"id": 3, "read_only": True}, {"id": 4}],
            [{"id": 3, "read_only": True}, {"id": 4, "read_only": "true"}],
            [{"id": n, "read_only": True} for n in range(1, 60)] + [{"id": 99, "read_only": False}],
        ):
            with self.subTest(keys=len(keys)):
                self.build()
                self.forge.keys = keys
                self.boot()
                self.pick_up()
                self.assertEqual({}, self.delivered())
                self.assertIn("untrusted: run #7 (repository has a write deploy key)", self.logs.getvalue())

    def test_read_only_deploy_keys_across_pages_keep_trust(self):
        for keys in ([], [{"id": n, "read_only": True} for n in range(1, 61)]):
            with self.subTest(keys=len(keys)):
                self.build()
                self.forge.keys = keys
                self.boot()
                self.pick_up()
                self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))
        self.assertIn(KEYS.format(2), self.lookups())

    def test_deploy_key_list_changing_during_pagination_is_not_trusted_yet(self):
        self.forge.keys = [{"id": n, "read_only": True} for n in range(1, 61)]
        self.boot()
        self.forge.reply_once("GET", KEYS.format(2), 200, [{"id": 60, "read_only": True}], **{"X-Total-Count": "61"})
        self.pick_up()
        self.assertEqual({}, self.delivered())
        self.assertIn("list changed during pagination", self.logs.getvalue())

    def test_only_running_tasks_are_searched(self):
        self.forge.tasks = [task(1000 + n, 900 + n, status="success") for n in range(80)] + [task()]
        self.boot()
        self.pick_up()
        self.assertEqual({"ncps-netrc", "ci-signing-key"}, set(self.delivered()))
        self.assertNotIn(TASKS.format(2), self.lookups())

    def test_delivery_errors_give_up_at_the_deadline(self):
        self.boot()
        self.trust_dir.chmod(0o755)
        self.pick_up()
        self.assertIn("delivery pending: trust directory has unexpected ownership or mode", self.logs.getvalue())
        self.tick(D.TRUST_DEADLINE)
        self.assertIn("untrusted: trust lookup gave up after 10 min", self.logs.getvalue())
        lookups = len(self.lookups())
        self.tick(D.POLL)
        self.tick(D.BUSY_POLL)
        self.assertEqual(lookups, len(self.lookups()))
        self.assertEqual({}, self.delivered())

    def test_gate_off_never_looks_up_or_delivers(self):
        self.build(trusted=False)
        self.boot()
        self.pick_up()
        self.tick(D.BUSY_POLL_FAST)
        self.assertEqual([], self.lookups())
        self.assertFalse(self.trust_dir.exists())


class SlotConfigurationTests(unittest.TestCase):
    """HOM-32: the slot, machine, forge, account and label come from the command line, not constants."""

    PILOT = ("ryza-eph-1", "ryza", "forge.ugalabugala.org", "manjo", "nix-eph")
    INACTIVE = b"LoadState=loaded\nActiveState=inactive\nJob=\nResult=success\n"

    def setUp(self):
        self.addCleanup(D.configure, *self.PILOT)
        self.logs = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.logs))

    def arguments(self, **changes):
        values = {
            "slot": "terra-eph-1", "machine": "terra", "slotctl": "/nix/store/x-forgejo-slotctl",
            "forge-host": "forge.noosphere.uk", "login": "manjo", "label": "nix-eph",
            "repo-id": "9", "state-dir": "/state",
        } | changes
        argv = []
        for key, value in values.items():
            if value is not None:
                argv += [f"--{key}", value]
        return argv

    def assert_pilot(self):
        self.assertEqual(self.PILOT, (D.SLOT, D.MACHINE, D.HOST, D.LOGIN, D.LABEL))
        self.assertEqual("microvm@ryza-eph-1.service", D.VM)
        self.assertEqual(VM, D.VM)
        self.assertEqual(
            tuple(f"microvm-{unit}@ryza-eph-1.service" for unit in ("tap-interfaces", "macvtap-interfaces", "pci-devices", "virtiofsd", "set-booted")),
            D.SUPPORT,
        )
        self.assertTrue(D.matches(D.NAME, f"eph-{'0' * 12}-ryza-{'f' * 32}"))

    def test_defaults_are_the_pilot(self):
        self.assert_pilot()

    def test_arguments_configure_one_slot(self):
        args = D.parse_arguments(self.arguments())
        self.assertEqual(Path("/nix/store/x-forgejo-slotctl"), args.slotctl)
        self.assertEqual(("terra-eph-1", "terra", "forge.noosphere.uk"), (D.SLOT, D.MACHINE, D.HOST))
        self.assertEqual("microvm@terra-eph-1.service", D.VM)
        self.assertIn("microvm-virtiofsd@terra-eph-1.service", D.SUPPORT)
        self.assertFalse(any("ryza" in unit for unit in D.SUPPORT))
        name = f"eph-{'a' * 12}-terra-{'b' * 32}"
        self.assertTrue(D.matches(D.NAME, name))
        self.assertFalse(D.matches(D.NAME, name.replace("terra", "ryza")))
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual("terra-eph-1", D.Store(Path(directory)).data["slot"])

    def test_dispatch_names_units_and_runner_after_the_slot(self):
        D.configure("terra-eph-1", "terra", "forge.ugalabugala.org", "manjo", "nix-eph")
        forge = FakeForge()
        self.addCleanup(forge.close)
        forge.jobs = [job(14)]
        calls = []

        def run(argv, **_options):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, stdout=self.INACTIVE if "show" in argv else b"")

        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        for directory in ("state", "vm", "credentials"):
            (root / directory).mkdir(mode=0o700)
        pat = root / "forgejo-pat"
        pat.write_text(PAT + "\n")
        config = write_slotctl_config(root / "slotctl.json", "terra-eph-1", root / "vm", root / "credentials" / "terra-eph-1")
        slot, slotctl = command_slot(config, run)
        dispatcher = D.Dispatcher(
            REPO,
            D.Forgejo(pat, forge.connect),
            slot,
            D.Store(root / "state"),
            FakeClock().monotonic,
            FakeClock().wall,
            pause=root / "pause",
        )
        dispatcher.tick()
        state = json.loads((root / "state" / "state.json").read_text())
        self.assertEqual("terra-eph-1", state["slot"])
        self.assertRegex(state["active"]["name"], r"^eph-[0-9a-f]{12}-terra-[0-9a-f]{32}$")
        self.assertEqual({"name": state["active"]["name"], "ephemeral": True}, forge.calls[-1][3])
        started = [argv for argv in calls if "start" in argv]
        self.assertEqual([("systemctl", "--system", "--no-pager", "--no-block", "--job-mode=fail", "start", "microvm@terra-eph-1.service")], started)
        shown = {argv[-1] for argv in calls if "show" in argv}
        self.assertEqual({"microvm@terra-eph-1.service", *D.SUPPORT}, shown)
        self.assertIn("terra-eph-1: queued VM start", self.logs.getvalue())
        self.assertTrue(all(argv[argv.index("--slot") + 1] == "terra-eph-1" for argv in slotctl.calls))
        self.assertEqual(TOKEN, (root / "credentials" / "terra-eph-1" / "runner-token").read_text())

    def test_rejects_separators_and_missing_settings(self):
        for changes in (
            {"slot": "ryza/eph-1"}, {"slot": "Ryza-eph-1"}, {"slot": "eph@1"}, {"machine": "ry za"},
            {"forge-host": "forge.example.org/x"}, {"forge-host": "localhost"}, {"forge-host": "forge.example.org:443"},
            {"login": "manjo/../x"}, {"login": "man jo"}, {"label": "nix,eph"}, {"label": "nix&eph"}, {"label": "nix-eph:host"},
            {"slotctl": "relative/slotctl"}, {"slot": None}, {"machine": None}, {"forge-host": None}, {"login": None},
            {"label": None}, {"slotctl": None}, {"vm-dir": "/vm"},
        ):
            with self.subTest(changes), self.assertRaises(SystemExit):
                D.parse_arguments(self.arguments(**changes))
            # A refused command line leaves the process as it was.
            self.assert_pilot()


class SlotctlTests(unittest.TestCase):
    """HOM-32: slotctl, the slot host side. Every input is checked there; secrets never reach argv or stderr."""

    SLOT = "ryza-eph-1"
    STAGE = {"uuid": uuid_for(100), "token": TOKEN, "handle": "opaque/attempt-1"}
    DELIVER = {"ci-signing-key": base64.b64encode(SIGNING_KEY).decode(), "ncps-netrc": base64.b64encode(NETRC).decode()}
    REFUSED = (2, b"", "invalid-request\n")

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.vm_dir = self.root / "vm"
        self.credential_dir = self.root / "credentials" / self.SLOT
        self.trust_dir = self.root / "credentials" / f"{self.SLOT}-trust"
        for directory in (self.vm_dir, self.credential_dir.parent):
            directory.mkdir(mode=0o700)
        self.config = write_slotctl_config(
            self.root / "slotctl.json", self.SLOT, self.vm_dir, self.credential_dir, self.trust_dir, deliver=True
        )
        self.off = write_slotctl_config(
            self.root / "off.json", self.SLOT, self.vm_dir, self.credential_dir, self.trust_dir, deliver=False
        )
        self.system = FakeSystemctl()
        self.stderrs = []

    def slotctl(self, *argv, payload=None, raw=None, config=None):
        """slotctl as built, with `config` standing in for the path the build compiles in."""
        out, err = io.BytesIO(), io.StringIO()
        data = raw if raw is not None else (b"" if payload is None else json.dumps(payload).encode())
        code = S.main(
            list(argv), stdin=io.BytesIO(data), stdout=out, stderr=err, run=self.system.run, config=str(config or self.config)
        )
        self.stderrs.append(err.getvalue())
        return code, out.getvalue(), err.getvalue()

    def tearDown(self):
        for secret in (TOKEN, SIGNING_SECRET, NETRC_PASSWORD):
            self.assertNotIn(secret, "".join(self.stderrs) + repr(self.system.calls))

    def test_observe_reads_vm_then_support_then_vm_again(self):
        self.system.set(D.SUPPORT[1], active="active")
        code, out, _ = self.slotctl("--slot", self.SLOT, "observe")
        self.assertEqual(0, code)
        shown = [argv[-1] for argv in self.system.calls]
        self.assertEqual([VM, *D.SUPPORT, VM], shown)
        answer = json.loads(out)
        self.assertEqual([True, "success"], answer["vm"])
        self.assertEqual([[unit, unit != D.SUPPORT[1]] for unit in D.SUPPORT], answer["support"])
        self.assertEqual([True, "success"], answer["again"])

    def test_refuses_bad_command_lines_and_configs(self):
        garbage = self.root / "garbage.json"
        garbage.write_text("{not json")
        entry = json.loads(self.config.read_text())["slots"][self.SLOT]
        shapes = {}
        for name, change in (
            ("relative", {"vm_dir": "vm"}),
            ("no-trust", {"trust_dir": None}),
            ("no-deliver", {"deliver": None}),
            ("string-deliver", {"deliver": "true"}),
            ("extra", {"extra": 1}),
        ):
            shapes[name] = self.root / f"{name}.json"
            shapes[name].write_text(json.dumps({"slots": {self.SLOT: {k: v for k, v in (entry | change).items() if v is not None}}}))
        closed = os.open(self.root / "fd", os.O_CREAT | os.O_RDWR)
        os.close(closed)
        for argv, config in (
            (("--slot", "terra-eph-1", "observe"), None),
            (("--slot", "Ryza", "observe"), None),
            (("--slot", self.SLOT, "reboot"), None),
            (("--slot", self.SLOT, "start", D.SUPPORT[0]), None),
            (("--slot", self.SLOT, "--hold-fd", "1", "observe"), None),
            (("--slot", self.SLOT, "--hold-fd", str(closed), "observe"), None),
            (("--slot", self.SLOT, "--hold-fd", "x", "observe"), None),
            (("observe",), None),
            (("--slot", self.SLOT, "observe"), garbage),
            (("--slot", self.SLOT, "observe"), self.root / "missing.json"),
            (("--slot", self.SLOT, "observe"), "@config@"),
            *((("--slot", self.SLOT, "observe"), path) for path in shapes.values()),
        ):
            with self.subTest(argv=argv, config=config):
                self.assertEqual(self.REFUSED, self.slotctl(*argv, config=config))
        self.assertEqual([], self.system.calls)

    def test_the_caller_cannot_choose_the_config(self):
        """The review's probe_argv.py: --config, repeated or abbreviated, used to win over the built-in one."""
        victim = self.root / "victim"
        victim.mkdir()
        (victim / "var.img").write_text("precious")
        evil = write_slotctl_config(self.root / "evil.json", self.SLOT, victim, self.root / "victim-cred" / "x")
        for argv in (
            ("--slot", self.SLOT, "--config", str(evil), "scrub"),
            ("--slot", self.SLOT, f"--config={evil}", "scrub"),
            ("--slot", self.SLOT, "--conf", str(evil), "scrub"),
            ("--slot", self.SLOT, f"--c={evil}", "scrub"),
            ("--config", str(evil), "--slot", self.SLOT, "scrub"),
        ):
            with self.subTest(argv=argv):
                self.assertEqual(self.REFUSED, self.slotctl(*argv))
                self.assertTrue((victim / "var.img").exists())
        self.assertEqual([], self.system.calls)

    def test_each_option_once_and_spelled_out(self):
        fd = os.open(self.root / "lock", os.O_CREAT | os.O_RDWR)
        self.addCleanup(os.close, fd)
        for argv in (
            ("--slot", self.SLOT, "--slot", "terra-eph-1", "observe"),
            (f"--slot={self.SLOT}", "--slot", self.SLOT, "observe"),
            ("--slot", self.SLOT, f"--slot={self.SLOT}", "observe"),
            ("--slot", self.SLOT, "--hold-fd", str(fd), "--hold-fd", str(fd), "observe"),
            ("--slot", self.SLOT, f"--hold-fd={fd}", "--hold-fd", str(fd), "observe"),
            ("--sl", self.SLOT, "observe"),
            ("--slot", self.SLOT, "--hold", str(fd), "observe"),
            ("--slot", self.SLOT, "-h"),
            ("--slot", self.SLOT, "--help", "observe"),
        ):
            with self.subTest(argv=argv):
                self.assertEqual(self.REFUSED, self.slotctl(*argv))
        self.assertEqual([], self.system.calls)
        # The = form of a single option is that same option.
        self.assertEqual(0, self.slotctl(f"--slot={self.SLOT}", f"--hold-fd={fd}", "observe")[0])

    def test_a_staged_token_cannot_become_a_config(self):
        """The review's probe_chain.py: stage a token that is a slotctl config, then point --config at it."""
        other = self.root / "other-vm"
        other.mkdir()
        (other / "var.img").write_text("another VM's persistent disk")
        evil = json.loads(write_slotctl_config(self.root / "e.json", "stygies", other, self.root / "anywhere" / "new").read_text())
        token = json.dumps(evil, separators=(",", ":"))
        self.assertTrue(S.matches(S.TOKEN, token))  # Still a valid runner token: the defence is the config.
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "stage", payload=self.STAGE | {"token": token})[0])
        staged = self.credential_dir / "runner-token"
        self.assertEqual(token, staged.read_text())
        for argv in (
            ("--slot", "stygies", "--config", str(staged), "stop"),
            ("--slot", "stygies", f"--config={staged}", "scrub"),
            ("--slot", "stygies", "stop"),
            ("--slot", "stygies", "scrub"),
        ):
            with self.subTest(argv=argv):
                self.assertEqual(self.REFUSED, self.slotctl(*argv))
        self.assertEqual([], self.system.mutations())
        self.assertTrue((other / "var.img").exists())

    def test_hold_fd_reaches_every_systemctl_call(self):
        seen = []
        run = self.system.run

        def record(argv, **options):
            seen.append(options["pass_fds"])
            return run(argv, **options)

        self.system.run = record
        fd = os.open(self.root / "lock", os.O_CREAT | os.O_RDWR)
        self.addCleanup(os.close, fd)
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "--hold-fd", str(fd), "observe")[0])
        self.assertEqual([(fd,)] * 7, seen)

    def test_stop_support_only_stops_this_slots_support_units(self):
        for units in ((), ("microvm@ryza-eph-1.service",), ("microvm-virtiofsd@other.service",), (D.SUPPORT[0], D.SUPPORT[0])):
            with self.subTest(units=units):
                self.assertEqual(self.REFUSED, self.slotctl("--slot", self.SLOT, "stop-support", *units))
        self.assertEqual([], self.system.mutations())
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "stop-support", D.SUPPORT[3], D.SUPPORT[0])[0])
        self.assertEqual([("systemctl", "--system", "--no-pager", "--no-block", "stop", D.SUPPORT[3], D.SUPPORT[0])], self.system.mutations())

    def test_stage_checks_every_field_before_writing(self):
        for payload, raw in (
            (None, b"{"),
            (None, b"x" * (S.MAX_INPUT + 1)),
            ([self.STAGE], None),
            ({k: v for k, v in self.STAGE.items() if k != "handle"}, None),
            (self.STAGE | {"extra": 1}, None),
            (self.STAGE | {"uuid": "../../etc"}, None),
            (self.STAGE | {"token": TOKEN + " with space"}, None),
            (self.STAGE | {"token": ""}, None),
            (self.STAGE | {"handle": "line\nbreak"}, None),
            (self.STAGE | {"handle": 7}, None),
        ):
            with self.subTest(payload=payload, raw=raw and raw[:5]):
                self.assertEqual(self.REFUSED, self.slotctl("--slot", self.SLOT, "stage", payload=payload, raw=raw))
                self.assertFalse(self.credential_dir.exists())
                self.assertFalse(self.trust_dir.exists())
        self.assertEqual((0, b"", ""), self.slotctl("--slot", self.SLOT, "stage", payload=self.STAGE))
        self.assertEqual(TOKEN, (self.credential_dir / "runner-token").read_text())
        self.assertEqual(0o400, stat.S_IMODE((self.credential_dir / "runner-uuid").stat().st_mode))
        self.assertEqual(0o700, stat.S_IMODE(self.trust_dir.stat().st_mode))
        self.assertEqual([], list(self.trust_dir.iterdir()))

    def test_scrub_waits_for_the_vm_and_refuses_a_symlinked_slot_dir(self):
        for name in S.IMAGES:
            (self.vm_dir / name).touch()
        self.system.set(active="active")
        self.assertEqual((1, b"", "vm-not-stopped\n"), self.slotctl("--slot", self.SLOT, "scrub"))
        self.assertTrue((self.vm_dir / "var.img").exists())
        self.system.set()
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "scrub")[0])
        self.assertFalse((self.vm_dir / "var.img").exists())
        # O_NOFOLLOW covers only the slot directory itself, the last path component. That suffices because
        # its parents are root-owned on the host (controlDir root:microvm-eph 0750, credParent root 0755).
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        (elsewhere / "var.img").touch()
        linked = write_slotctl_config(self.root / "linked.json", self.SLOT, self.root / "linked-vm", self.credential_dir)
        (self.root / "linked-vm").symlink_to(elsewhere)
        self.assertEqual((1, b"", "scrub-failed\n"), self.slotctl("--slot", self.SLOT, "scrub", config=linked))
        self.assertTrue((elsewhere / "var.img").exists())

    def test_cleanup_clears_the_trust_share_even_with_delivery_off(self):
        def fill():
            self.trust_dir.mkdir(mode=0o700, exist_ok=True)
            for name in (*S.TRUST_FILES, ".ncps-netrc.tmp"):
                (self.trust_dir / name).write_bytes(b"left over from when trust was on")

        fill()
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "withdraw", config=self.off)[0])
        self.assertEqual([], list(self.trust_dir.iterdir()))
        fill()
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "scrub", config=self.off)[0])
        self.assertFalse(self.trust_dir.exists())
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "stage", payload=self.STAGE, config=self.off)[0])
        self.assertFalse(self.trust_dir.exists())
        self.system.set(active="active")
        self.assertEqual((1, b"", "no-trust-share\n"), self.slotctl("--slot", self.SLOT, "deliver", payload=self.DELIVER, config=self.off))
        self.assertFalse(self.trust_dir.exists())

    def test_deliver_checks_shapes_and_a_settled_running_vm(self):
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "stage", payload=self.STAGE)[0])
        for payload in (
            {"ci-signing-key": self.DELIVER["ci-signing-key"]},
            self.DELIVER | {"extra": "eA=="},
            self.DELIVER | {"ci-signing-key": "not base64!"},
            self.DELIVER | {"ncps-netrc": base64.b64encode(b"machine evil.example\nlogin x\npassword y\n").decode()},
            self.DELIVER | {"ci-signing-key": base64.b64encode(b"no-colon-here").decode()},
        ):
            with self.subTest(payload=sorted(payload)):
                self.assertEqual(self.REFUSED, self.slotctl("--slot", self.SLOT, "deliver", payload=payload))
        # Only ActiveState=active with no job queued: not before boot, not while starting or stopping.
        for state in (
            {}, {"active": "failed"}, {"active": "inactive", "pending": "71"}, {"active": "activating", "pending": "71"},
            {"active": "activating"}, {"active": "deactivating", "pending": "72"}, {"active": "active", "pending": "73"},
            {"active": "reloading"},
        ):
            with self.subTest(state=state):
                self.system.set(**state)
                self.assertEqual((1, b"", "vm-not-running\n"), self.slotctl("--slot", self.SLOT, "deliver", payload=self.DELIVER))
                self.assertEqual([], list(self.trust_dir.iterdir()))
        self.system.set(active="active")
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "deliver", payload=self.DELIVER)[0])
        self.assertEqual(SIGNING_KEY, (self.trust_dir / "ci-signing-key").read_bytes())
        self.assertEqual(0o400, stat.S_IMODE((self.trust_dir / "ncps-netrc").stat().st_mode))
        self.assertEqual(0, self.slotctl("--slot", self.SLOT, "withdraw")[0])
        self.assertEqual([], list(self.trust_dir.iterdir()))
        # A trust share that is a symlink is refused, and its target stays empty.
        target = self.root / "target"
        target.mkdir(mode=0o700)
        self.trust_dir.rmdir()
        self.trust_dir.symlink_to(target)
        self.assertEqual((1, b"", "trust-dir-missing\n"), self.slotctl("--slot", self.SLOT, "deliver", payload=self.DELIVER))
        self.assertEqual([], list(target.iterdir()))


class CommandSlotTests(unittest.TestCase):
    """HOM-32: the dispatcher's side of slotctl. Answers are checked as strictly as Forgejo's."""

    def call(self, code=0, stdout=b"", stderr=b"", error=None):
        calls = []

        def run(argv, **options):
            calls.append((argv, options))
            if error is not None:
                raise error
            return subprocess.CompletedProcess(argv, code, stdout, stderr)

        return D.CommandSlot(("/nix/store/x-slotctl",), run, lock_fd=9), calls

    def snapshot(self, **changes):
        answer = {"vm": [True, "success"], "support": [[unit, True] for unit in D.SUPPORT], "again": [False, "timeout"]} | changes
        return json.dumps(answer).encode()

    def test_observe_and_its_argv(self):
        slot, calls = self.call(stdout=self.snapshot())
        snapshot = slot.observe()
        self.assertEqual((True, "success", False, "timeout", []), (
            snapshot.vm_idle, snapshot.vm_result, snapshot.again_idle, snapshot.again_result, snapshot.residual,
        ))
        argv, options = calls[0]
        self.assertEqual(("/nix/store/x-slotctl", "--slot", D.SLOT, "--hold-fd", "9", "observe"), argv)
        self.assertEqual((9,), options["pass_fds"])
        self.assertEqual(b"", options["input"])
        self.assertFalse(options["check"])

    def test_unexpected_observe_answers_refuse_slot_reuse(self):
        support = [[unit, True] for unit in D.SUPPORT]
        for stdout in (
            b"", b"[]", b"{", b"x" * (D.MAX_RESPONSE + 1),
            self.snapshot(extra=1),
            self.snapshot(vm=[True]),
            self.snapshot(vm=["yes", "success"]),
            self.snapshot(again=[True, "rebooted"]),
            self.snapshot(support=support[::-1]),
            self.snapshot(support=support[:-1]),
            self.snapshot(support=[[unit, 1] for unit in D.SUPPORT]),
            self.snapshot(support=[[unit, True, 0] for unit in D.SUPPORT]),
        ):
            with self.subTest(stdout=stdout[:60]):
                slot, _ = self.call(stdout=stdout)
                with self.assertRaisesRegex(D.SlotError, "answered unexpectedly"):
                    slot.observe()

    def test_refusal_codes_are_logged_in_the_dispatchers_own_words(self):
        support = f"microvm-virtiofsd@{D.SLOT}.service"
        for act, code, message in (
            (lambda slot: slot.scrub(), "vm-not-stopped", "VM state changed during reconciliation; waiting before slot cleanup"),
            (lambda slot: slot.start(), "systemctl-failed", f"systemctl start failed or timed out for {D.SLOT}; reconciling unit state"),
            (lambda slot: slot.observe(), "systemctl-failed", f"systemctl show failed or timed out for {D.SLOT}; reconciling unit state"),
            (lambda slot: slot.stop_support([support]), "systemctl-failed", f"systemctl stop failed or timed out for {D.SLOT}; reconciling unit state"),
            (lambda slot: slot.observe(), "unknown-state-vm", f"unknown systemd state for {D.VM}; refusing slot reuse"),
            (lambda slot: slot.observe(), "unknown-state-virtiofsd", f"unknown systemd state for {support}; refusing slot reuse"),
            (lambda slot: slot.deliver({"ci-signing-key": SIGNING_KEY, "ncps-netrc": NETRC}), "trust-dir-unsafe",
             "trust directory has unexpected ownership or mode; refusing to deliver"),
        ):
            with self.subTest(code=code):
                slot, _ = self.call(code=1, stderr=code.encode() + b"\n")
                with self.assertRaises(D.SlotError) as raised:
                    act(slot)
                self.assertEqual(message, str(raised.exception))

    def test_anything_else_is_generic(self):
        refused = f"slotctl scrub refused for {D.SLOT}; reconciling unit state"
        for code, stderr, message in (
            (1, b"", refused),
            (1, b"vm-on-fire\n", refused),
            (1, b"unknown-state-bogus\n", refused),
            (1, b"trusted: run #12 (push); delivered CI upload credentials\n", refused),
            (1, b"vm-not-stopped\nextra\n", refused),
            (1, b"vm-not-stopped" + b" " * 64, refused),
            (1, "vm-not-stoppéd".encode(), refused),
            (2, b"vm-not-stopped\n", f"slotctl scrub failed (exit 2) for {D.SLOT}; reconciling unit state"),
            (3, b"unexpected-failure\n", f"slotctl scrub failed (exit 3) for {D.SLOT}; reconciling unit state"),
            (-9, b"", f"slotctl scrub failed (exit -9) for {D.SLOT}; reconciling unit state"),
        ):
            with self.subTest(code=code, stderr=stderr[:30]):
                slot, _ = self.call(code=code, stderr=stderr)
                with self.assertRaises(D.SlotError) as raised:
                    slot.scrub()
                self.assertEqual(message, str(raised.exception))
        for error in (subprocess.TimeoutExpired("slotctl", 30), OSError("exec failed")):
            slot, _ = self.call(error=error)
            with self.assertRaisesRegex(D.SlotError, "slotctl start failed or timed out"):
                slot.start()

    def test_secrets_go_on_stdin_only(self):
        slot, calls = self.call()
        slot.stage(uuid_for(100), TOKEN, "opaque/attempt-1")
        slot.deliver({"ci-signing-key": SIGNING_KEY, "ncps-netrc": NETRC})
        (stage_argv, stage), (deliver_argv, deliver) = calls
        self.assertEqual("stage", stage_argv[-1])
        self.assertEqual("deliver", deliver_argv[-1])
        self.assertNotIn(TOKEN, repr(stage_argv) + repr(deliver_argv))
        self.assertEqual({"uuid": uuid_for(100), "token": TOKEN, "handle": "opaque/attempt-1"}, json.loads(stage["input"]))
        self.assertEqual(NETRC, base64.b64decode(json.loads(deliver["input"])["ncps-netrc"]))
        slot, calls = self.call()
        with self.assertRaisesRegex(D.ApiError, "invalid runner token"):
            slot.stage(uuid_for(100), "bad token", "opaque/attempt-1")
        self.assertEqual([], calls)


class SharedConstantsTests(unittest.TestCase):
    """HOM-32: what the dispatcher and slotctl both define must agree; drift would fail closed, but quietly."""

    def test_dispatcher_and_slotctl_agree(self):
        self.assertEqual(D.SUPPORT_UNITS, S.SUPPORT_UNITS)
        self.assertEqual(D.RESULTS, (*S.RESULTS, "other result"))
        self.assertEqual(D.TRUST_FILES, S.TRUST_FILES)
        self.assertEqual({k: v.pattern for k, v in D.TRUST_SHAPES.items()}, {k: v.pattern for k, v in S.TRUST_SHAPES.items()})
        for name in ("TOKEN", "UUID", "SLOT_NAME"):
            self.assertEqual(getattr(D, name).pattern, getattr(S, name).pattern, name)
        for value in ("opaque/attempt-1", "", "x" * 1024, "x" * 1025, "line\nbreak", "\ud800", 7, None):
            self.assertEqual(D.handle_ok(value), S.handle_ok(value), repr(value)[:20])

    def test_every_refusal_code_has_the_dispatchers_words(self):
        slot = D.CommandSlot(("slotctl",))
        for code in S.CODES:
            with self.subTest(code=code):
                self.assertIsNotNone(slot._refusal("scrub", code.encode() + b"\n"))
        unknown_state = {code for code in S.CODES if code.startswith("unknown-state-")}
        self.assertEqual(set(D.CommandSlot.REFUSALS), set(S.CODES) - unknown_state - {"systemctl-failed"})
        self.assertEqual(set(D.CommandSlot.ACTIONS), set(S.VERBS) - {"stage", "withdraw"})


class SlotctlProcessTests(unittest.TestCase):
    """HOM-32: slotctl as the real child process the dispatcher runs, with a stand-in systemctl on PATH."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        systemctl = bin_dir / "systemctl"
        systemctl.write_text(
            "#!/bin/sh\n"
            'case " $* " in *" show "*) printf "LoadState=loaded\\nActiveState=inactive\\nJob=\\nResult=success\\n" ;; esac\n'
        )
        systemctl.chmod(0o755)
        self.enterContext(patch.dict(os.environ, {"PATH": f"{bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}"}))
        self.vm_dir, self.credential_dir = root / "vm", root / "credentials" / D.SLOT
        for directory in (self.vm_dir, self.credential_dir.parent):
            directory.mkdir(mode=0o700)
        self.config = write_slotctl_config(root / "slotctl.json", D.SLOT, self.vm_dir, self.credential_dir)
        # What replaceVars builds: the same file with the config path compiled in.
        source = SLOTCTL.read_text()
        self.assertEqual(1, source.count("@config@"))
        self.script = root / "_forgejo-slotctl.py"
        self.script.write_text(source.replace("@config@", str(self.config)))
        self.lock = os.open(root / "lock", os.O_CREAT | os.O_RDWR)
        self.addCleanup(os.close, self.lock)
        self.slot = D.CommandSlot((sys.executable, "-I", "-B", str(self.script)), lock_fd=self.lock)

    def test_round_trip(self):
        snapshot = self.slot.observe()
        self.assertTrue(snapshot.vm_idle and snapshot.again_idle)
        self.assertEqual([], snapshot.residual)
        self.slot.stage(uuid_for(100), TOKEN, "opaque/attempt-1")
        self.assertEqual(TOKEN, (self.credential_dir / "runner-token").read_text())
        (self.vm_dir / "var.img").touch()
        self.slot.scrub()
        self.assertFalse(self.credential_dir.exists())
        self.assertFalse((self.vm_dir / "var.img").exists())
        self.slot.start()
        self.slot.withdraw()

    def test_a_refusal_and_a_forged_command_line(self):
        with self.assertRaisesRegex(D.SlotError, "^this slot does not deliver CI credentials"):
            self.slot.deliver({"ci-signing-key": SIGNING_KEY, "ncps-netrc": NETRC})
        forged = subprocess.run(
            (sys.executable, "-I", "-B", str(self.script), "--config", str(self.config), "--slot", D.SLOT, "observe"),
            stdin=subprocess.DEVNULL, capture_output=True, timeout=30, check=False,
        )
        self.assertEqual((2, b"", b"invalid-request\n"), (forged.returncode, forged.stdout, forged.stderr))

    def test_an_unbuilt_slotctl_never_runs(self):
        unbuilt = D.CommandSlot((sys.executable, "-I", "-B", str(SLOTCTL)))
        with self.assertRaisesRegex(D.SlotError, "^slotctl observe failed \\(exit 2\\)"):
            unbuilt.observe()


if __name__ == "__main__":
    unittest.main()
