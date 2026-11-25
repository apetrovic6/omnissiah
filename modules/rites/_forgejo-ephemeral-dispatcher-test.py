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
            "status": "offline",
            "version": "",
            "labels": None,
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
        if method == "GET" and path.startswith(RUNNERS + "/"):
            runner_id = int(path.rsplit("/", 1)[1])
            runner = self.runners.get(runner_id)
            return (200 if runner is not None else 404), runner, {}
        if method == "DELETE" and path.startswith(RUNNERS + "/"):
            runner_id = int(path.rsplit("/", 1)[1])
            return (204 if self.runners.pop(runner_id, None) is not None else 404), None, {}
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
        self.dispatcher.tick()

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
        self.assertEqual(self.clock.wall() + D.VM_DEADLINE, active["deadline"])
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

    def test_declared_runner_without_assignment_data_keeps_systemd_timeout(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.forge.runners[100].update(status="idle", version="13.2.1", labels=["nix-eph"])
        self.forge.jobs = None
        self.leave_images()
        self.restart()
        self.tick(D.VM_DEADLINE + 1)
        self.assertTrue(self.credential_dir.exists())
        self.assertTrue((self.vm_dir / "var.img").exists())
        self.assertEqual([], self.forge.paths("DELETE"))
        self.assertEqual(1, len(self.system.mutations()))
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
        self.tick(D.BUSY_POLL - 1)
        self.assertEqual(calls, self.forge.paths())
        self.tick(1)
        self.assertEqual(calls + [USER, JOBS, RUNNERS + "/100"], self.forge.paths())
        [stop] = self.system.mutations("stop")
        self.assertEqual(("stop", VM), stop[-2:])
        self.assertIn("vanished before runner 100 declared", self.logs.getvalue())
        self.tick(7)
        self.assertTrue((self.vm_dir / "var.img").exists())
        self.assertTrue(self.credential_dir.exists())
        self.assertEqual([], self.forge.paths("DELETE"))
        self.system.set()
        self.tick(7)
        self.assert_scrubbed()
        self.assertIsNone(self.state()["active"])
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))

    def test_missing_job_and_unusable_runner_detail_do_not_stop_vm(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.forge.jobs = None
        endpoint = RUNNERS + "/100"
        undeclared = self.forge.runners.pop(100)
        # A fast job may finish and its runner may disappear between observations.
        for status, fields in (
            (404, {}),
            (503, {}),
            (200, {"status": "active"}),
            (200, {"status": "offline", "labels": ["nix-eph"]}),
            (200, {"status": "idle", "version": "13.2.1"}),
            (200, {"uuid": uuid_for(999)}),
            (200, {"owner_id": OWNER + 1}),
            (200, {"status": None}),
            (200, {"version": None}),
        ):
            with self.subTest(status=status, fields=fields):
                self.forge.reply_once("GET", endpoint, status, undeclared | fields)
                self.tick(D.BUSY_POLL)
                self.assertEqual(endpoint, self.forge.paths()[-1])
                self.assertEqual([], self.system.mutations("stop"))
                self.assertEqual([], self.forge.paths("DELETE"))
        del undeclared["labels"]
        self.forge.reply_once("GET", endpoint, 200, undeclared)
        self.tick(D.BUSY_POLL)
        self.assertEqual([], self.system.mutations("stop"))

    def test_running_evidence_survives_restart_and_prevents_cancellation(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.forge.jobs = [job(status="running", task_id=71)]
        self.tick(7)
        self.assertTrue(self.state()["active"]["assigned"])
        self.forge.jobs = None
        self.restart()
        self.tick(7)
        self.assertEqual([USER, JOBS], self.forge.paths()[-2:])
        self.assertEqual([], self.system.mutations("stop"))
        self.assertEqual([], self.forge.paths("DELETE"))

    def test_unavailable_or_malformed_jobs_are_not_cancellation_evidence(self):
        self.forge.jobs = [job()]
        self.tick()
        self.system.set(active="active")
        self.forge.reply_once("GET", JOBS, 503)
        self.tick(7)
        self.forge.jobs = [job(repo_id=None)]
        self.tick(D.BUSY_POLL)
        self.assertNotIn(RUNNERS + "/100", self.forge.paths("GET"))
        self.assertEqual([], self.system.mutations("stop"))
        self.system.set()
        self.tick()
        self.assertEqual([RUNNERS + "/100"], self.forge.paths("DELETE"))
        self.assert_scrubbed()

    def test_uncertain_start_and_pending_jobs_block_cleanup_and_second_start(self):
        self.forge.jobs = [job(), job(2, "other")]
        self.system.start_mode = "uncertain"
        self.tick()
        deadline = self.state()["active"]["deadline"]
        self.restart()
        self.tick(7)  # ActiveState=inactive with a queued start is not idle.
        self.system.set(active="activating", pending="71")
        self.tick(7)
        self.system.set(active="active")
        self.tick(7)
        self.assertEqual(deadline, self.state()["active"]["deadline"])
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
        self.forge.reply_once("POST", RUNNERS, 201, b"{broken JSON " + TOKEN.encode())
        self.tick()
        entry = self.state()["active"]
        runner_id = self.forge.add_runner(entry["name"])
        with patch.object(self.dispatcher.api, "delete", side_effect=Crash), self.assertRaises(Crash):
            self.tick(D.INVENTORY_POLL)
        self.assertEqual(
            [{"id": runner_id, "uuid": uuid_for(runner_id)}], self.state()["ambiguous"][entry["handle"]]["runners"]
        )
        del self.forge.runners[runner_id]  # DELETE succeeded remotely, but the client never got the reply.
        self.restart()
        self.tick()
        self.assertEqual([RUNNERS + f"/{runner_id}"], self.forge.paths("DELETE"))
        self.assertIn("HTTP 404", self.logs.getvalue())
        self.assertEqual({}, self.state()["ambiguous"])
        self.assertEqual([RUNNERS], self.forge.paths("POST"))

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
        self.assertEqual([job()["handle"]], self.state()["retired"])
        self.assertEqual({}, self.state()["ambiguous"])

    def test_explicit_post_rejections_retire_each_handle_without_inventory(self):
        self.forge.jobs = []
        retired = []
        for index, status in enumerate((400, 401, 403, 404, 422, 429), start=1):
            with self.subTest(status=status):
                queued = job(index, f"rejected-{status}")
                self.forge.jobs.append(queued)
                retired.append(queued["handle"])
                self.forge.reply_once("POST", RUNNERS, status, {"error": TOKEN})
                self.tick(60)
                self.assertIsNone(self.state()["active"])
                self.assertEqual({}, self.state()["ambiguous"])
                self.assertEqual(retired, self.state()["retired"])
                self.assertEqual([RUNNERS] * index, self.forge.paths("POST"))
                self.assertIn(f"register runner: HTTP {status}", self.logs.getvalue())
        self.restart()
        self.tick(7)
        self.assertEqual([RUNNERS] * len(retired), self.forge.paths("POST"))
        self.assertEqual(1, self.forge.paths("GET").count(LIST.format(1)))
        self.assertEqual([], self.system.mutations())
        self.forge.jobs = [job(20, "unrelated")]
        self.tick(7)
        self.assertEqual("unrelated", self.state()["active"]["handle"])

    def test_http_request_timeout_is_ambiguous(self):
        self.forge.jobs = [job()]
        self.forge.reply_once("POST", RUNNERS, 408, {"error": TOKEN})
        self.tick()
        self.assertEqual("intent", self.state()["active"]["phase"])
        self.tick(7)
        self.assertEqual([RUNNERS], self.forge.paths("POST"))
        self.assertIn(job()["handle"], self.state()["ambiguous"])
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


if __name__ == "__main__":
    unittest.main()
