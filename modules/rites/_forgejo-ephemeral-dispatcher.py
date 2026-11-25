#!/usr/bin/env python3
"""Dispatch one targeted Forgejo job at a time to one fixed disposable slot (--slot).

With --trusted-jobs (HOM-31), every job still boots untrusted. Once the slot's runner has taken the job, the
dispatcher maps it exactly: the job's task_id gives the task (GET /repos/manjo/<repo>/actions/tasks), the
task's run_number gives the run (GET .../actions/runs?run_number=N). A run is trusted only if trusted_run()
returns None. Only then are the CI signing key and the ncps upload netrc written to the slot's root-only trust
directory, which the guest sees as a read-only virtiofs share. Any doubt means nothing is delivered.

The dispatcher only decides. Every slot side effect (systemd units, staged credentials, disk images, the trust
share) goes through slotctl (--slotctl, _forgejo-slotctl.py), one validated verb per call.
"""

import argparse
import base64
from contextlib import closing, contextmanager
import fcntl
import hashlib
import http.client
import json
import os
import re
import secrets
import selectors
import shlex
import signal
import stat
import subprocess
import sys
import time
from pathlib import Path

# One process serves one slot. configure() sets these from the command line before anything runs. The
# defaults are the HOM-30 pilot's (and the tests').
SLOT = "ryza-eph-1"
MACHINE = "ryza"
VM = f"microvm@{SLOT}.service"
SUPPORT_UNITS = ("tap-interfaces", "macvtap-interfaces", "pci-devices", "virtiofsd", "set-booted")
SUPPORT = tuple(f"microvm-{name}@{SLOT}.service" for name in SUPPORT_UNITS)
HOST = "forge.ugalabugala.org"
RUNNERS = "/user/actions/runners"
LOGIN = "manjo"
LABEL = "nix-eph"
POLL = 7
BUSY_POLL_FAST = 15
BUSY_FAST_WINDOW = 5 * 60
BUSY_POLL = 60
STOP_RETRY = 90  # Longer than the slot's TimeoutStopSec (30 s) plus SIGKILL.
INVENTORY_POLL = 5 * 60
INTENT_EXPIRY = 24 * 60 * 60
REFUSAL_LIMIT = 3
REFUSAL_SPAN = 60 * 60
PRE_START_MAX_BACKOFF = 60
PAUSE_FILE = Path("/run/forgejo-ephemeral-dispatcher/pause")
HOST_PAUSE_FILE = Path("/run/forgejo-ephemeral/pause")
CLAIM_ROOT = Path("/run/forgejo-ephemeral/claims")
REQUEST_TIMEOUT = 10
MAX_RESPONSE = 2 * 1024 * 1024
VM_DEADLINE = 90 + 75 * 60 + 30  # Informational only; systemd enforces the actual deadlines.
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
CLAIM_NAME = re.compile(r"[0-9a-f]{12}")
TOKEN = re.compile(r"[!-~]{1,4096}")
UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
# Trusted-job credential delivery (HOM-31).
ACTIONS_USER = -2  # Forgejo's "forgejo-actions" user, the trigger user of every scheduled run.
REPO_NAME = re.compile(r"[A-Za-z0-9._-]{1,100}")
TRUST_FILES = ("ncps-netrc", "ci-signing-key")  # Write order: the guest hook needs both.
TRUST_SOURCES = {"ncps-netrc": "trusted-ncps-netrc", "ci-signing-key": "trusted-ci-signing-key"}
# What slotctl observe may report as a unit's last result (slotctl folds anything else into "other result").
RESULTS = ("success", "timeout", "exit-code", "signal", "core-dump", "resources", "start-limit-hit", "other result")
TRUST_SHAPES = {
    "ci-signing-key": re.compile(rb"[A-Za-z0-9._-]{1,255}:[A-Za-z0-9+/]{20,400}={0,2}\n?"),
    "ncps-netrc": re.compile(rb"machine ncps\.noosphere\.uk\nlogin [!-~]{1,255}\npassword [!-~]{1,4096}\n?"),
}
TRUST_DEADLINE = 10 * 60
TASK_PAGES = 5
NO_RUN = "none"
MAX_RUN_RESPONSE = 8 * 1024 * 1024  # One run, but its event_payload carries PR bodies and commit lists.
# What configure() accepts. Each value ends up in a unit name, a runner name, a URL path or the jobs query,
# so none may carry a separator: no "/", "?", "&", ",", "@" or whitespace.
SLOT_NAME = re.compile(r"[a-z][a-z0-9-]{0,62}")
HOST_NAME = re.compile(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+")
LOGIN_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,39}")
LABEL_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")


def runner_namespace(slot):
    # Keep recognizing the Ryza pilot's durable registrations after the unit rename.
    return "ryza" if slot == "ryza-eph-1" else slot


def runner_pattern(slot):
    return re.compile(rf"eph-[0-9a-f]{{12}}-{re.escape(runner_namespace(slot))}-[0-9a-f]{{32}}")


NAME = runner_pattern(SLOT)


def configure(slot, machine, forge_host, login, label):
    """Point this process at one slot on one machine, one forge account and one label."""
    for name, pattern, value in (
        ("slot", SLOT_NAME, slot),
        ("machine", SLOT_NAME, machine),
        ("forge host", HOST_NAME, forge_host),
        ("login", LOGIN_NAME, login),
        ("label", LABEL_NAME, label),
    ):
        if not isinstance(value, str) or pattern.fullmatch(value) is None:
            raise ValueError(f"invalid {name}")
    global SLOT, MACHINE, VM, SUPPORT, HOST, LOGIN, LABEL, NAME
    SLOT, MACHINE, HOST, LOGIN, LABEL = slot, machine, forge_host, login, label
    VM = f"microvm@{SLOT}.service"
    SUPPORT = tuple(f"microvm-{name}@{SLOT}.service" for name in SUPPORT_UNITS)
    NAME = runner_pattern(SLOT)


class ApiError(Exception):
    """Only fixed labels and HTTP status may be included in API diagnostics."""


class HttpError(ApiError):
    def __init__(self, operation, status):
        self.status = status
        hint = f"; verify the {LOGIN} PAT and its write:user (and, for trust, read:repository) scope" if status in (401, 403) else ""
        super().__init__(f"Forgejo {operation}: HTTP {status}{hint}")


class SlotError(Exception):
    """A safe diagnostic for a slot that cannot be reused yet."""


class StartRefused(SlotError):
    """slotctl explicitly refused before asking systemd to queue a start."""


class StateError(Exception):
    """Durable state could not be trusted or updated; restart without more side effects."""


def positive(value):
    return type(value) is int and value > 0


def nonnegative(value):
    return type(value) is int and value >= 0


def timestamp(value):
    return type(value) in (int, float) and 0 < value <= sys.float_info.max


def matches(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def handle_ok(value):
    return isinstance(value, str) and 0 < len(value) <= 1024 and value.isprintable()


def handle_digest(handle):
    return hashlib.sha256(handle.encode()).hexdigest()[:12]


def runner_id_ok(value):
    return (
        isinstance(value, dict)
        and value.keys() == {"id", "uuid"}
        and positive(value["id"])
        and matches(UUID, value["uuid"])
    )


def log(message):
    print(f"{SLOT}: {message}", file=sys.stderr, flush=True)


def expired(_signum, _frame):
    raise TimeoutError


class Forgejo:
    def __init__(self, pat_file, connect=None):
        self.pat_file = pat_file
        self.pat = None
        # Direct connections only: no environment proxy, redirects or URL-valued inputs.
        self.connect = connect or (lambda: http.client.HTTPSConnection(HOST, timeout=REQUEST_TIMEOUT))

    def _authorization(self):
        if self.pat is None:
            try:
                with self.pat_file.open("rb") as file:
                    pat = file.read(4097).strip()
            except (AttributeError, OSError):
                raise ApiError("host forgejo-pat credential is unavailable; check LoadCredential") from None
            if not re.fullmatch(rb"[!-~]{1,4096}", pat):
                raise ApiError("host forgejo-pat credential is empty or invalid")
            self.pat = pat.decode("ascii")
        return "token " + self.pat

    def _request(self, operation, method, path, accepted, payload=None, limit=MAX_RESPONSE):
        headers = {"Authorization": self._authorization(), "Accept": "application/json"}
        body = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode()
        # A socket timeout alone permits an arbitrarily slow trickle of response bytes.
        previous = signal.signal(signal.SIGALRM, expired)
        signal.setitimer(signal.ITIMER_REAL, REQUEST_TIMEOUT)
        try:
            with closing(self.connect()) as connection:
                connection.request(method, "/api/v1" + path, body, headers)
                with connection.getresponse() as response:
                    status, response_headers = response.status, response.headers
                    if status not in accepted:
                        raise HttpError(operation, status)
                    if method == "DELETE":
                        return status, response_headers
                    data = response.read(limit + 1)
                    if len(data) > limit:
                        raise ApiError(f"Forgejo {operation}: oversized response")
                    return json.loads(data), response_headers
        except (OSError, http.client.HTTPException):
            raise ApiError(f"Forgejo {operation}: connection failed or timed out") from None
        except (ValueError, RecursionError):
            raise ApiError(f"Forgejo {operation}: invalid JSON response") from None
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous)

    def identify(self, expected):
        user, _ = self._request("identity", "GET", "/user", (200,))
        if not isinstance(user, dict) or user.get("login") != LOGIN or not positive(user.get("id")):
            raise ApiError(f"Forgejo identity is not the expected {LOGIN} account; check the PAT")
        if expected is not None and user["id"] != expected:
            raise ApiError(f"Forgejo {LOGIN} account ID changed; reconcile ownership before restarting")
        return user["id"]

    def jobs(self, repo_id, owner):
        rows, _ = self._request("jobs", "GET", f"{RUNNERS}/jobs?labels={LABEL}", (200,))
        if rows is None:  # Forgejo serializes the empty result as a nil slice.
            return []
        if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
            raise ApiError("Forgejo jobs: unexpected response")
        jobs = []
        for row in rows:
            if (
                not positive(row.get("repo_id"))
                or not isinstance(row.get("runs_on"), list)
                or not all(isinstance(label, str) for label in row["runs_on"])
                or not positive(row.get("owner_id"))
                or row["owner_id"] != owner
                or row.get("status") not in ("waiting", "running")
                or not handle_ok(row.get("handle"))
                or not positive(row.get("id"))
                or not nonnegative(row.get("attempt"))
                or not nonnegative(row.get("task_id"))
            ):
                raise ApiError("Forgejo jobs: unexpected job metadata")
            if row["repo_id"] == repo_id:
                jobs.append(row)
        return jobs

    def runners(self):
        """Read all pages before deleting, so our deletes cannot move rows between pages."""
        rows = {}
        expected_total = None
        for page in range(1, 101):
            batch, headers = self._request(
                "list owned runners", "GET", f"{RUNNERS}?visible=false&page={page}&limit=50", (200,)
            )
            total = headers.get("X-Total-Count", "")
            if not isinstance(batch, list) or not re.fullmatch(r"[0-9]{1,9}", total):
                raise ApiError("Forgejo list owned runners: invalid inventory or pagination")
            total = int(total)
            if expected_total is not None and total != expected_total:
                raise ApiError("Forgejo list owned runners: inventory changed during pagination")
            expected_total = total
            for row in batch:
                if (
                    not isinstance(row, dict)
                    or not positive(row.get("id"))
                    or row["id"] in rows
                    or not matches(UUID, row.get("uuid"))
                    or not isinstance(row.get("name"), str)
                    or type(row.get("ephemeral")) is not bool
                    or not nonnegative(row.get("owner_id"))
                    or not nonnegative(row.get("repo_id"))
                ):
                    raise ApiError("Forgejo list owned runners: invalid row or inventory changed during pagination")
                rows[row["id"]] = row
            # The server supplies Link and X-Total-Count. Never use the URL from Link,
            # even on the same origin: synthesize only the next fixed inventory request.
            next_page = any('; rel="next"' in link for link in headers.get_all("Link", ()))
            if len(rows) == total and not next_page:
                return rows.values()
            if not batch or len(rows) >= total:
                raise ApiError("Forgejo list owned runners: inconsistent pagination; retrying")
        raise ApiError("Forgejo list owned runners: inventory exceeds 100 pages; reconcile manually")

    def register(self, name):
        result, _ = self._request("register runner", "POST", RUNNERS, (201,), {"name": name, "ephemeral": True})
        if not isinstance(result, dict):
            raise ApiError("Forgejo register runner: invalid registration response")
        runner = {key: result.get(key) for key in ("id", "uuid")}
        if not runner_id_ok(runner):
            raise ApiError("Forgejo register runner: invalid ID or UUID; reconciling by name")
        return runner, result.get("token")

    def delete(self, runner):
        status, _ = self._request("delete runner", "DELETE", f"{RUNNERS}/{runner['id']}", (204, 404))
        log(f"runner {runner['id']} cleanup: HTTP {status}")

    # The /repos routes need the PAT's read:repository scope (Forgejo v15.0.12 routers/api/v1/api.go:1075-1076).

    def repository(self, name, repo_id, owner):
        repo, _ = self._request("repository", "GET", f"/repos/{LOGIN}/{name}", (200,))
        if (
            not isinstance(repo, dict)
            or repo.get("id") != repo_id
            or not isinstance(repo.get("owner"), dict)
            or repo["owner"].get("id") != owner
            or repo["owner"].get("login") != LOGIN
        ):
            raise ApiError(f"Forgejo repository: {LOGIN}/{name} is not the configured repository ID owned by {LOGIN}")

    def task(self, name, task_id):
        """The task a runner created for a job. Tasks are listed newest first (`id` DESC)."""
        for page in range(1, TASK_PAGES + 1):
            body, _ = self._request("tasks", "GET", f"/repos/{LOGIN}/{name}/actions/tasks?status=running&page={page}&limit=50", (200,))
            if not isinstance(body, dict) or not isinstance(body.get("workflow_runs"), list):
                raise ApiError("Forgejo tasks: unexpected response")
            for row in body["workflow_runs"]:
                if not isinstance(row, dict) or not positive(row.get("id")):
                    raise ApiError("Forgejo tasks: unexpected task metadata")
                if row["id"] == task_id:
                    if (
                        not positive(row.get("run_number"))
                        or not isinstance(row.get("head_sha"), str)
                        or not isinstance(row.get("workflow_id"), str)
                    ):
                        raise ApiError("Forgejo tasks: unexpected task metadata")
                    return row
            if not body["workflow_runs"] or any(row["id"] < task_id for row in body["workflow_runs"]):
                break
        raise ApiError("Forgejo tasks: the job's task is not listed")

    def deploy_keys_read_only(self, name):
        """True only if every deploy key on the repository is read-only (GET /repos/{o}/{r}/keys, all pages).

        Forgejo attributes a deploy-key push to the repository owner (routers/private/serv.go:266-270), so a
        write deploy key could produce a "push by manjo". The route needs the owner's read:repository PAT.
        """
        seen, total = set(), None
        for page in range(1, 21):
            rows, headers = self._request("deploy keys", "GET", f"/repos/{LOGIN}/{name}/keys?page={page}&limit=50", (200,))
            count = headers.get("X-Total-Count", "")
            if not isinstance(rows, list) or not re.fullmatch(r"[0-9]{1,6}", count):
                raise ApiError("Forgejo deploy keys: invalid list or pagination")
            if total is not None and int(count) != total:
                raise ApiError("Forgejo deploy keys: list changed during pagination")
            total = int(count)
            for row in rows:
                if not isinstance(row, dict) or not positive(row.get("id")) or row["id"] in seen:
                    raise ApiError("Forgejo deploy keys: unexpected key metadata")
                seen.add(row["id"])
                if row.get("read_only") is not True:
                    return False
            if len(seen) == total:
                return True
            if not rows:
                raise ApiError("Forgejo deploy keys: inconsistent pagination")
        raise ApiError("Forgejo deploy keys: too many keys to check")

    def run_by_number(self, name, number):
        """The run whose per-repository index is `number`: unique per repository."""
        body, _ = self._request(
            "runs", "GET", f"/repos/{LOGIN}/{name}/actions/runs?run_number={number}&limit=50", (200,),
            limit=MAX_RUN_RESPONSE,
        )
        if (
            not isinstance(body, dict)
            or body.get("total_count") != 1
            or not isinstance(body.get("workflow_runs"), list)
            or len(body["workflow_runs"]) != 1
            or not isinstance(body["workflow_runs"][0], dict)
            or body["workflow_runs"][0].get("index_in_repo") != number
            or not positive(body["workflow_runs"][0].get("id"))
        ):
            raise ApiError("Forgejo runs: no single run for the task's run number")
        return body["workflow_runs"][0]


def trusted_run(run, repo_id, owner):
    """None when the run is trusted, else a fixed reason. Fields are server-set; nothing the job controls.

    Forgejo v15.0.12 semantics:
    - is_fork_pull_request is true for fork PRs AND for every AGit PR (models/issues/pull.go:473-488). Re-runs
      keep it, and keep event and trigger_user (services/actions/rerun.go:56-122). So a fork PR re-run by manjo
      stays untrusted.
    - approved_by only records who let a fork run start (services/actions/run.go:43-60). It never grants trust.
    - trigger_user is the event's doer (services/actions/notifier_helper.go:377), the dispatcher for
      workflow_dispatch (services/actions/workflows.go:146-152), and the forgejo-actions user (-2) for
      schedules, which always run the default branch (notifier_helper.go:610-623, schedule_tasks.go:134-143).
      "manjo" therefore means any holder of a manjo write credential, agents with a manjo token included. Forgejo
      also attributes deploy-key pushes to the repository owner (routers/private/serv.go:266-270), which is why
      _resolve refuses trust while the repository has any write deploy key.
    - Only the default branch is trusted. prettyref is the run's ref short name (models/actions/run.go:134-140): a
      branch or tag push and a dispatch on a branch or tag resolve to refs/heads|tags/<name> and show <name>, but a
      dispatch accepts any ref git resolves (routers/api/v1/repo/action.go DispatchWorkflow, modules/git/
      repo_ref.go:69-82). "pull/5/head" or a commit SHA stays verbatim and never equals the default branch name.
      Residual: a tag named exactly like the default branch looks the same; only a writer can create one.
    """
    try:
        repository, user = run["repository"], run["trigger_user"]
        repo_owner = repository["owner"]
        event, trigger_event, schedule = run["event"], run["trigger_event"], run["ScheduleID"]
        if not (
            positive(repository["id"])
            and isinstance(repo_owner["login"], str)
            and type(repo_owner["id"]) is int
            and type(user["id"]) is int
            and type(run["is_fork_pull_request"]) is bool
            and type(run["need_approval"]) is bool
            and isinstance(event, str)
            and isinstance(trigger_event, str)
            and type(schedule) is int
            and isinstance(run["prettyref"], str)
            and isinstance(repository["default_branch"], str)
            and repository["default_branch"]
            and run["prettyref"]
        ):
            return "invalid run metadata"
    except (KeyError, TypeError):
        return "invalid run metadata"
    if repository["id"] != repo_id or repo_owner["id"] != owner or repo_owner["login"] != LOGIN:
        return "repository mismatch"
    if run["is_fork_pull_request"]:
        return "fork or AGit pull request"
    if run["need_approval"]:
        return "awaiting approval"
    on_default = run["prettyref"] == repository["default_branch"]
    if event == "push" and trigger_event == "push":
        if schedule != 0:
            return "push run carries a schedule"
        if user["id"] != owner:
            return "push not by manjo"
        return None if on_default else "push not on the default branch"
    if trigger_event == "schedule" and event in ("push", "schedule"):
        if schedule <= 0:
            return "schedule run without a schedule"
        if user["id"] != ACTIONS_USER:
            return "schedule not triggered by forgejo-actions"
        return None if on_default else "schedule not on the default branch"
    if event == "workflow_dispatch" and trigger_event == "workflow_dispatch":
        if user["id"] != owner:
            return "dispatch not by manjo"
        # Any ref git resolves is accepted: refs/pull/N/head ("#N"), "pull/5/head", a SHA, another branch or a tag.
        return None if on_default else "dispatch not on the default branch"
    return "event is not push, schedule or workflow_dispatch"


def run_ssh(argv, *, input, timeout, **_):
    """Pump all three pipes with one deadline; kill the SSH client on overflow or timeout."""
    deadline = time.monotonic() + timeout
    with subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        try:
            out, err = bytearray(), bytearray()
            pending = memoryview(input)
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ, (out, 16 * 1024))
                selector.register(process.stderr, selectors.EVENT_READ, (err, 4 * 1024))
                if pending:
                    os.set_blocking(process.stdin.fileno(), False)
                    selector.register(process.stdin, selectors.EVENT_WRITE)
                else:
                    process.stdin.close()
                while selector.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(argv, timeout)
                    for key, events in selector.select(remaining):
                        stream = key.fileobj
                        if events & selectors.EVENT_WRITE:
                            try:
                                pending = pending[os.write(key.fd, pending):]
                            except BlockingIOError:
                                continue
                            except BrokenPipeError:
                                pending = pending[:0]
                            if not pending:
                                selector.unregister(stream)
                                stream.close()
                        else:
                            target, limit = key.data
                            chunk = os.read(key.fd, limit + 1 - len(target))
                            if not chunk:
                                selector.unregister(stream)
                                stream.close()
                                continue
                            target.extend(chunk)
                            if len(target) > limit:
                                raise SlotError("SSH slotctl output exceeded its limit; refusing slot reuse")
            status = process.wait(timeout=max(0, deadline - time.monotonic()))
            return subprocess.CompletedProcess(argv, status, bytes(out), bytes(err))
        finally:
            if process.poll() is None:
                process.kill()


class Snapshot:
    """What slotctl observe saw, in order: the VM, each support unit, then the VM again."""

    def __init__(self, vm, support, again, run):
        (self.vm_idle, self.vm_result), self.support, (self.again_idle, self.again_result) = vm, support, again
        self.run = run

    @property
    def residual(self):
        return [unit for unit, idle in self.support if not idle]


class CommandSlot:
    """The slot host side. Every slot side effect goes through slotctl (_forgejo-slotctl.py), one verb per call.

    Secrets go to slotctl on stdin, never in argv. Unexpected answers refuse slot reuse. Only fixed refusal
    codes are mapped to log messages; slotctl's text is never logged. SSH pipes are bounded by run_ssh.
    """

    TIMEOUTS = {"observe": 80}  # Seven systemctl calls of at most 10 s each.
    MAX_CODE = 64
    # The systemctl action behind each verb, for the "systemctl-failed" message.
    ACTIONS = {
        "observe": "show", "start": "start", "stop": "stop", "reset-failed": "reset-failed",
        "stop-support": "stop", "scrub": "show", "deliver": "show",
    }
    REFUSALS = {
        "vm-not-stopped": "VM state changed during reconciliation; waiting before slot cleanup",
        "vm-not-running": "slot is not running; not delivering CI credentials",
        "no-trust-share": "this slot does not deliver CI credentials; its trust share is off on the slot host",
        "scrub-failed": "cannot scrub exact slot images or credentials; check slot paths for unexpected files",
        "withdraw-failed": "cannot remove delivered CI credentials; check the trust directory",
        "trust-dir-missing": "trust directory is missing; refusing to deliver CI credentials",
        "trust-dir-unsafe": "trust directory has unexpected ownership or mode; refusing to deliver",
        "deliver-failed": "cannot deliver CI credentials; check the trust directory",
        "trust-dir-create-failed": "cannot create the empty trust directory; check the credential parent",
        "stage-failed": "cannot stage runner credentials; check ownership and permissions of the credential parent",
        "slot-user-missing": "slot user or group is missing; check the slot host configuration",
        "slot-busy": "another slotctl verb holds the slot lock",
        "slot-lock": "cannot safely lock the slot",
        "disk-space-check": "cannot check free space for slot images; refusing to start",
        "disk-space-low": "insufficient free space for slot images; refusing to start",
        "run-mismatch": "slot run changed; refusing mutation",
        "run-exists": "a slot run is already staged; refusing to replace it",
        "run-marker": "cannot read or update the slot run marker",
        "remote-launch": "cannot launch the sandboxed slotctl verb",
    }
    # These codes in a start reply come from gates before systemctl. In
    # particular, systemctl-failed can mean the reply to a queued job was lost.
    START_REFUSALS = frozenset((
        b"slot-busy", b"slot-lock", b"slot-user-missing", b"run-marker", b"run-mismatch",
        b"disk-space-check", b"disk-space-low", b"remote-launch",
    ))

    def __init__(self, command, run=None, lock_fd=None, *, remote=False):
        self.command = tuple(command)
        self.remote = remote
        self.run = run if run is not None else (run_ssh if remote else subprocess.run)
        self.lock_fd = lock_fd

    def _call(self, verb, *args, payload=None):
        hold = () if self.lock_fd is None or self.remote else ("--hold-fd", str(self.lock_fd))
        command = ("--slot", SLOT, *hold, verb, *args)
        argv = (shlex.join(command),) if self.remote else command
        try:
            result = self.run(
                (*self.command, *argv),
                input=b"" if payload is None else json.dumps(payload).encode(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                # slotctl hands the state lock on to the systemctl calls it makes (see Systemctl there).
                pass_fds=(self.lock_fd,) if hold else (),
                timeout=120 if self.remote else self.TIMEOUTS.get(verb, 30),
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            raise SlotError(f"slotctl {verb} failed or timed out for {SLOT}; reconciling unit state") from None
        if result.returncode == 0:
            if verb != "observe" and result.stdout:
                raise SlotError(f"slotctl {verb} answered unexpectedly for {SLOT}; refusing slot reuse")
            return result.stdout
        # OpenSSH uses 255 for transport errors; its diagnostics are not slotctl protocol.
        if self.remote and result.returncode == 255:
            raise SlotError(f"SSH transport failed for {SLOT}; refusing slot reuse")
        if result.returncode == 1:
            message = self._refusal(verb, result.stderr)
            if message is not None and verb == "start" and result.stderr.removesuffix(b"\n") in self.START_REFUSALS:
                raise StartRefused(message)
            raise SlotError(message or f"slotctl {verb} refused for {SLOT}; reconciling unit state")
        if verb == "start" and result.returncode == 2 and result.stderr == b"invalid-request\n":
            raise StartRefused(f"slotctl start rejected the request for {SLOT} before submission")
        raise SlotError(f"slotctl {verb} failed (exit {result.returncode}) for {SLOT}; reconciling unit state")

    def _refusal(self, verb, stderr):
        if not isinstance(stderr, bytes) or len(stderr) > self.MAX_CODE:
            return None
        try:
            code = stderr.removesuffix(b"\n").decode("ascii")
        except UnicodeDecodeError:
            return None
        if code == "systemctl-failed":
            return f"systemctl {self.ACTIONS.get(verb, verb)} failed or timed out for {SLOT}; reconciling unit state"
        if code.startswith("unknown-state-"):
            kind = code.removeprefix("unknown-state-")
            unit = VM if kind == "vm" else (f"microvm-{kind}@{SLOT}.service" if kind in SUPPORT_UNITS else None)
            return None if unit is None else f"unknown systemd state for {unit}; refusing slot reuse"
        return self.REFUSALS.get(code)

    def observe(self):
        output = self._call("observe")
        try:
            data = json.loads(output[: MAX_RESPONSE + 1]) if len(output) <= MAX_RESPONSE else None
            vm, support, again, run = data["vm"], data["support"], data["again"], data["run"]
            if (
                data.keys() == {"vm", "support", "again", "run"}
                and (run is None or matches(NAME, run))
                and all(
                    isinstance(state, list) and len(state) == 2 and type(state[0]) is bool and state[1] in RESULTS
                    for state in (vm, again)
                )
                and isinstance(support, list)
                and [entry[0] if isinstance(entry, list) and len(entry) == 2 else None for entry in support] == list(SUPPORT)
                and all(type(entry[1]) is bool for entry in support)
            ):
                return Snapshot(tuple(vm), tuple((unit, idle) for unit, idle in support), tuple(again), run)
        except (ValueError, RecursionError, TypeError, KeyError, AttributeError):
            pass
        raise SlotError(f"slotctl observe answered unexpectedly for {SLOT}; refusing slot reuse")

    def start(self, run):
        self._call("start", run)

    def stop(self, run):
        self._call("stop", run)

    def check_space(self):
        self._call("check-space")

    def reset_failed(self):
        self._call("reset-failed")

    def stop_support(self, units):
        self._call("stop-support", *units)

    def stage(self, run, runner_uuid, token, handle):
        if not matches(TOKEN, token):
            raise ApiError("Forgejo register runner: missing or invalid runner token")
        self._call("stage", run, payload={"uuid": runner_uuid, "token": token, "handle": handle})

    def scrub(self, run):
        self._call("scrub", run if run is not None else NO_RUN)

    def deliver(self, run, secrets):
        self._call("deliver", run, payload={name: base64.b64encode(secrets[name]).decode("ascii") for name in TRUST_FILES})

    def withdraw(self, run):
        self._call("withdraw", run if run is not None else NO_RUN)



class Store:
    def __init__(self, directory, *, slot=None):
        self.directory = directory
        slot = SLOT if slot is None else slot
        try:
            with (directory / "state.json").open("rb") as file:
                self.data = json.load(file)
        except FileNotFoundError:
            self.data = {
                "version": 2, "slot": slot, "owner_id": None, "active": None,
                "ambiguous": {}, "retired": [], "refusals": {},
            }
            return
        except (OSError, ValueError, RecursionError):
            raise StateError("cannot read state.json; reconcile persisted state before restarting") from None
        if not self._valid(self.data, slot):
            raise StateError("invalid state.json; reconcile persisted state before restarting")

    @staticmethod
    def _valid(data, slot):
        name = runner_pattern(slot)
        if (
            not isinstance(data, dict)
            or data.keys() != {"version", "slot", "owner_id", "active", "ambiguous", "retired", "refusals"}
            or not positive(data["version"])
            or data["version"] != 2
            or data["slot"] != slot
            or not positive(data["owner_id"])
            or not isinstance(data["retired"], list)
            or not all(handle_ok(handle) for handle in data["retired"])
            or not isinstance(data["ambiguous"], dict)
            or not isinstance(data["refusals"], dict)
        ):
            return False
        for handle, budget in data["refusals"].items():
            if (
                not handle_ok(handle)
                or not isinstance(budget, dict)
                or budget.keys() != {"count", "first_at"}
                or not positive(budget["count"])
                or budget["count"] > REFUSAL_LIMIT
                or not timestamp(budget["first_at"])
            ):
                return False
        for handle, intent in data["ambiguous"].items():
            if (
                not handle_ok(handle)
                or not isinstance(intent, dict)
                or intent.keys() not in ({"name", "runners"}, {"name", "runners", "absent_since"})
                or not matches(name, intent["name"])
                or (
                    "absent_since" in intent
                    and (intent["runners"] is not None or not positive(intent["absent_since"]))
                )
                or (
                    intent["runners"] is not None
                    and (
                        not isinstance(intent["runners"], list)
                        or not intent["runners"]
                        or not all(map(runner_id_ok, intent["runners"]))
                    )
                )
            ):
                return False
        active = data["active"]
        if active is None:
            return True
        if (
            not isinstance(active, dict)
            or active.keys() != {"handle", "name", "runner", "phase", "queued_at"}
            or not handle_ok(active["handle"])
            or not matches(name, active["name"])
            or active["phase"] not in ("intent", "registered", "start", "cleanup", "release")
        ):
            return False
        if active["phase"] == "intent":
            return active["runner"] is None and active["queued_at"] is None
        return runner_id_ok(active["runner"]) and (
            timestamp(active["queued_at"]) if active["phase"] == "start" else active["queued_at"] is None
        )

    def save(self, **changes):
        data = self.data | changes
        try:
            directory = os.open(self.directory, DIR_FLAGS)
            try:
                fd = os.open(
                    "state.json.tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600, dir_fd=directory
                )
                with os.fdopen(fd, "w") as file:
                    json.dump(data, file, separators=(",", ":"))
                    file.flush()
                    os.fsync(file.fileno())
                os.replace("state.json.tmp", "state.json", src_dir_fd=directory, dst_dir_fd=directory)
                os.fsync(directory)
            finally:
                os.close(directory)
        except OSError:
            raise StateError("cannot persist state.json; check the dispatcher state directory") from None
        self.data = data


class Claims:
    """Pool-wide arbitration. The durable state, not a PID or the age of a file, owns a claim."""

    def __init__(self, root, states):
        self.directory = root / f"{HOST}:{LOGIN}"
        self.states = states

    @contextmanager
    def _locked(self):
        try:
            self.directory.mkdir(mode=0o700, exist_ok=True)
            fd = os.open(self.directory, DIR_FLAGS)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
                yield fd
            finally:
                os.close(fd)
        except OSError:
            raise StateError("cannot update the dispatcher claim directory; refusing dispatch") from None

    def _ledger(self, store):
        claims, blocked = set(), set()
        for slot, directory in self.states.items():
            data = store.data if slot == SLOT else Store(directory, slot=slot).data
            handles = list(data["ambiguous"])
            if data["active"] is not None:
                handles.append(data["active"]["handle"])
            for handle in handles:
                digest = handle_digest(handle)
                if digest in claims:
                    raise StateError("conflicting durable claims; reconcile dispatcher state before polling")
                claims.add(digest)
            blocked.update(data["retired"])
            # The slot that saw a definite refusal owns that handle's retry budget.
            if slot != SLOT:
                blocked.update(data["refusals"])
        return claims, blocked

    @staticmethod
    def _create(fd, digest):
        try:
            os.close(os.open(digest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd))
            return True
        except FileExistsError:
            return False

    def recover(self, store):
        # Rebuild before polling, even after a host reboot where /run is empty and
        # a peer with an active or ambiguous registration has not started yet.
        with self._locked() as fd:
            claims, _ = self._ledger(store)
            for digest in os.listdir(fd):
                if CLAIM_NAME.fullmatch(digest) and digest not in claims:
                    os.unlink(digest, dir_fd=fd)
            for digest in claims:
                self._create(fd, digest)

    def reserve(self, store, jobs):
        with self._locked() as fd:
            claims, blocked = self._ledger(store)
            for job in jobs:
                handle = job["handle"]
                digest = handle_digest(handle)
                if handle in blocked or digest in claims:
                    continue
                if not self._create(fd, digest):
                    # A process may have died after O_EXCL but before saving
                    # its intent. The locked ledger proves there was no POST.
                    os.unlink(digest, dir_fd=fd)
                    if not self._create(fd, digest):
                        raise StateError("claim changed outside the dispatcher lock")
                active = dict(
                    handle=handle, name=f"eph-{digest}-{runner_namespace(SLOT)}-{secrets.token_hex(16)}",
                    runner=None, phase="intent", queued_at=None,
                )
                store.save(active=active)
                return job, digest, active
        return None

    def finish(self, store, handles, **changes):
        with self._locked() as fd:
            # Persist the proof of cleanup before dropping the claim; a crash
            # between the two only leaves a stale, reclaimable marker.
            store.save(**changes)
            for handle in handles:
                try:
                    os.unlink(handle_digest(handle), dir_fd=fd)
                except FileNotFoundError:
                    pass


class Trust:
    """Trusted-job settings: the repository's name and where systemd put the credential sources."""

    def __init__(self, repo, sources):
        self.repo, self.sources = repo, sources

    def secrets(self):
        """The CI upload credentials, or None if either is missing or malformed."""
        secrets = {}
        for name, source in TRUST_SOURCES.items():
            try:
                with (self.sources / source).open("rb") as file:
                    value = file.read(8193)
            except (OSError, TypeError):
                return None
            if not TRUST_SHAPES[name].fullmatch(value):
                return None
            secrets[name] = value
        return secrets


class Dispatcher:
    def __init__(
        self, repo_id, api, slot, store, claims, monotonic=time.monotonic, wall=time.time, *,
        pause=PAUSE_FILE, host_pause=HOST_PAUSE_FILE, trust=None,
    ):
        # `slot` does every slot side effect (CommandSlot: slotctl); this class only decides.
        self.repo_id, self.api, self.slot, self.store = repo_id, api, slot, store
        self.monotonic, self.wall = monotonic, wall
        self.pause, self.host_pause = pause, host_pause
        self.claims = claims
        self.claims.recover(store)
        self.api_after = self.api_delay = 0
        self.inventory_after = self.busy_after = 0
        self.busy_misses = 0
        self.observed = None
        self.stop_queued = None  # (slot run name, monotonic time) of the last cancellation stop
        self.reset_pending = False  # reset-failed still owed for a cancellation stop that timed out
        self.identity_verified = False
        self.deadline_logged = False
        self.trust = trust
        # In memory only: after a restart the delivered files are withdrawn (main) and the run is re-resolved.
        self.verdict = None  # {"name", "state": pending|delivered|untrusted, "since": pickup first seen}
        self.repository_verified = False
        self.repository_after = 0
        # Slot-local backoff for requests that never reached systemd. A peer
        # can still take the job once we delete the unused registration.
        self.pre_start_retries = {}

    @staticmethod
    def _unknown_run(snapshot, active):
        return snapshot.run is not None and (active is None or snapshot.run != active["name"])

    def withdraw(self):
        # A previous delivery is not this dispatcher's verdict.
        snapshot = self.slot.observe()
        if self._unknown_run(snapshot, self.store.data["active"]):
            if snapshot.vm_idle and snapshot.again_idle:
                return  # The idle reconciliation pass will scrub this run.
            raise SlotError("live or pending VM has an unknown slot run; refusing slot reuse")
        self.slot.withdraw(snapshot.run)

    def tick(self):
        idle = True
        try:
            idle = self._local()
            now = self.monotonic()
            if not idle:
                if now >= self.busy_after:
                    queued_at = self.store.data["active"]["queued_at"]
                    interval = BUSY_POLL_FAST if self.wall() - queued_at < BUSY_FAST_WINDOW else BUSY_POLL
                    if self._resolving():
                        interval = POLL  # Deliver soon after pickup: builds before delivery aren't uploaded.
                    self.busy_after = now + interval
                    try:
                        self._remote(False)
                    except ApiError:
                        self.busy_misses = 0
                        raise
            elif now >= self.api_after:
                try:
                    self._remote(True)
                except ApiError:
                    self.api_delay = min(60, max(POLL, 2 * self.api_delay))
                    self.api_after = self.monotonic() + self.api_delay
                    raise
                else:
                    self.api_after = self.api_delay = 0
        except (ApiError, SlotError) as error:
            log(error)
        return POLL if idle else max(0, min(POLL, self.busy_after - self.monotonic()))

    def _local(self):
        active = self.store.data["active"]
        # One slotctl call reads the VM, each support unit, then the VM again.
        snapshot = self.slot.observe()
        if not snapshot.vm_idle:
            if self._unknown_run(snapshot, active):
                raise SlotError("live or pending VM has an unknown slot run; refusing slot reuse")
            if active is None or active["phase"] != "start":
                raise SlotError("VM is live or has a pending job without a recorded start; refusing slot reuse")
            if snapshot.run != active["name"]:
                raise SlotError("live VM has no matching slot run; refusing slot reuse")
            if self.observed != active["name"]:
                self.observed = active["name"]
                self.deadline_logged = False
                self.busy_after = 0
                self.busy_misses = 0
                log(f"monitoring VM for runner {active['runner']['id']}; systemd owns its deadline")
            if self.wall() >= active["queued_at"] + VM_DEADLINE and not self.deadline_logged:
                self.deadline_logged = True
                log("VM is still busy past its recorded deadline estimate; inspect the systemd unit")
            return False
        residual = snapshot.residual
        if residual:
            if snapshot.again_idle:
                self.slot.stop_support(residual)
            raise SlotError("waiting for slot support units to stop")
        # Re-observed after inspecting support units, also before any destructive cleanup
        # (and slotctl's scrub checks the VM once more).
        idle, result = snapshot.again_idle, snapshot.again_result
        if not idle:
            raise SlotError("VM state changed during reconciliation; waiting before slot cleanup")
        if self._unknown_run(snapshot, active):
            log("scrubbing idle slot with unknown run marker")
        self.slot.scrub(snapshot.run)
        self.verdict = None
        if result == "success":
            self.reset_pending = False
        else:
            if active is not None and active["phase"] == "start":
                # First idle pass for this slot run. Only the expected outcome of OUR cancellation stop
                # is cleared: a guest cancelled mid-boot ignores the ACPI powerdown and ends failed/timeout
                # once TimeoutStopSec escalates. Anything else (preflight refusals, signals, OOM,
                # RuntimeMaxSec), and anything after a dispatcher restart (stop_queued is in memory only),
                # stays failed for inspection and alerting.
                stopped = self.stop_queued
                self.reset_pending = result == "timeout" and stopped is not None and stopped[0] == active["name"]
                if not self.reset_pending:
                    log(f"slot ended {result}; left failed for inspection")
            if self.reset_pending:
                # Not fatal: retried on the next idle pass until Result is success again.
                try:
                    self.slot.reset_failed()
                except SlotError as error:
                    log(error)
                else:
                    self.reset_pending = False
                    log(f"reset {VM} after its cancellation stop timed out")
        if active is None or active["phase"] in ("cleanup", "release"):
            return True
        if active["phase"] == "intent":
            ambiguous = self.store.data["ambiguous"] | {active["handle"]: {"name": active["name"], "runners": None}}
            self.store.save(active=None, ambiguous=ambiguous)
            log(f"registration outcome unresolved for {active['name']}; searching owned runners by exact name")
        elif active["phase"] == "registered":
            self.store.save(active=active | {"phase": "release"})
            log(f"VM start not submitted; local files scrubbed for unused runner {active['runner']['id']}")
        else:
            cleanup = active | {"phase": "cleanup", "queued_at": None}
            self.store.save(active=cleanup)
            log(f"VM idle ({result}); local files scrubbed for runner {active['runner']['id']}")
        return True

    def _remote(self, idle):
        data = self.store.data
        owner = self.api.identify(data["owner_id"])
        if not self.identity_verified:
            log(f"Forgejo PAT identity verified as {LOGIN}")
            self.identity_verified = True
        if self.trust is not None and not self.repository_verified and self.monotonic() >= self.repository_after:
            # Up front, so a PAT without read:repository shows before the pause is lifted. Not fatal:
            # untrusted dispatch goes on, and every resolution still requires the verification.
            try:
                self._verify_repository(owner)
            except ApiError as error:
                self.repository_after = self.monotonic() + INVENTORY_POLL
                log(f"cannot verify the trusted-job repository: {error}")
        if data["owner_id"] is None:
            if self.monotonic() < self.inventory_after:
                return
            if any(row["owner_id"] == owner and matches(NAME, row["name"]) for row in self._inventory()):
                raise ApiError("state.json absent but a dispatcher-named runner exists; reconcile before enabling dispatch")
            self.store.save(owner_id=owner)
        if idle and data["active"] is not None:
            active = data["active"]
            self.api.delete(active["runner"])
            handle = active["handle"]
            if active["phase"] == "release":
                self.claims.finish(self.store, (handle,), active=None)
                previous, _ = self.pre_start_retries.get(handle, (0, 0))
                delay = min(PRE_START_MAX_BACKOFF, max(POLL, previous * 2))
                self.pre_start_retries[handle] = delay, self.monotonic() + delay
                log(f"released job after unused runner {active['runner']['id']} was deleted; retry in {delay}s")
            else:
                self.claims.finish(self.store, (handle,), active=None, retired=[*data["retired"], handle])
        inventory_ok = False
        if idle:
            self._delete_recovered()
            if (
                self.monotonic() >= self.inventory_after
                and any(intent["runners"] is None for intent in self.store.data["ambiguous"].values())
            ):
                try:
                    self._recover_by_name(owner)
                except ApiError as error:
                    # Inventory has its own cooldown; keep checking jobs and servicing known IDs.
                    log(error)
                else:
                    inventory_ok = True
                    self._delete_recovered()
        jobs = self.api.jobs(self.repo_id, owner)
        seen = {job["handle"] for job in jobs}
        self._observe_queue(seen, inventory_ok)
        if not idle:
            self._check_cancelled(seen)
            if self.trust is not None:
                self._settle_trust(jobs, owner)
            return
        data = self.store.data
        blocked = set(data["retired"]) | data["ambiguous"].keys()
        now = self.monotonic()
        eligible = [
            job for job in jobs
            if job["status"] == "waiting" and job["task_id"] == 0
            and job["runs_on"] == [LABEL] and job["handle"] not in blocked
            and now >= self.pre_start_retries.get(job["handle"], (0, 0))[1]
        ]
        if eligible and not self._paused():
            self.slot.check_space()
            self._dispatch(sorted(eligible, key=lambda job: job["id"]))

    def _check_cancelled(self, seen):
        active = self.store.data["active"]
        if active["handle"] in seen:
            self.busy_misses = 0
        else:
            self.busy_misses += 1
            # Once per slot run: the unit stays deactivating for up to TimeoutStopSec, and every
            # further poll would queue (and log) the same stop. Re-queue only if the slot is somehow
            # still busy after STOP_RETRY, which outlasts the 30 s stop timeout and its SIGKILL.
            stopped = self.stop_queued
            if stopped is not None and stopped[0] == active["name"] and self.monotonic() - stopped[1] < STOP_RETRY:
                return
            if self.busy_misses >= 2 and not self.slot.observe().vm_idle:
                self.slot.stop(active["name"])
                self.stop_queued = (active["name"], self.monotonic())
                log(f"queued VM stop: runner {active['runner']['id']} target absent from consecutive job polls")

    def _resolving(self):
        if self.trust is None:
            return False
        verdict = self.verdict
        if verdict is None or verdict["name"] != self.store.data["active"]["name"]:
            return True
        return verdict["state"] == "pending" and (
            verdict["since"] is None or self.monotonic() - verdict["since"] < TRUST_DEADLINE
        )

    def _settle_trust(self, jobs, owner):
        """Deliver the CI upload credentials only to a slot whose exact run is trusted.

        Every boot is untrusted. Resolution waits for the slot's runner to take the job (status running,
        task_id set), then follows task_id -> task -> run_number -> run, cross-checks task and run, and
        rechecks job and run just before writing. Errors retry until TRUST_DEADLINE after pickup, then give up.
        """
        active = self.store.data["active"]
        if self.verdict is None or self.verdict["name"] != active["name"]:
            self.verdict = {"name": active["name"], "state": "pending", "since": None}
        verdict = self.verdict
        if verdict["state"] != "pending":
            return
        job = self._picked_up(jobs, active["handle"])
        if job is None:
            return
        if verdict["since"] is None:
            verdict["since"] = self.monotonic()
        try:
            reason, run = self._resolve(job, owner)
            if reason is None:
                # Recheck: still the same attempt, still running on the same task, still the same trusted run.
                again = self._picked_up(self.api.jobs(self.repo_id, owner), active["handle"])
                if again is None or any(again[key] != job[key] for key in ("id", "attempt", "task_id")):
                    raise ApiError("job changed before delivery")
                rerun = self.api.run_by_number(self.trust.repo, run["index_in_repo"])
                if rerun["id"] != run["id"]:
                    raise ApiError("run changed before delivery")
                reason = trusted_run(rerun, self.repo_id, owner)
        except ApiError as error:
            self._defer(verdict, f"trust lookup pending: {error}", error)
            return
        if reason is not None:
            verdict["state"] = "untrusted"
            log(f"untrusted: run #{run['index_in_repo']} ({reason}); CI upload credentials withheld")
            return
        secrets = self.trust.secrets()
        if secrets is None:
            verdict["state"] = "untrusted"
            log("untrusted: trusted-ci-signing-key or trusted-ncps-netrc credential missing or malformed; withheld")
            return
        try:
            if self.slot.observe().vm_idle:
                return  # The next tick reconciles the stopped slot; never write into a directory being scrubbed.
            self.slot.deliver(active["name"], secrets)
        except SlotError as error:
            self._defer(verdict, f"delivery pending: {error}", error)
            return
        verdict["state"] = "delivered"
        log(f"trusted: run #{run['index_in_repo']} ({run['trigger_event']}); delivered CI upload credentials")

    def _defer(self, verdict, message, error):
        if self.monotonic() - verdict["since"] >= TRUST_DEADLINE:
            verdict["state"] = "untrusted"
            log(f"untrusted: trust lookup gave up after {TRUST_DEADLINE // 60} min ({error}); CI upload credentials withheld")
        else:
            log(message)

    def _verify_repository(self, owner):
        self.api.repository(self.trust.repo, self.repo_id, owner)
        self.repository_verified = True
        log(f"repository {LOGIN}/{self.trust.repo} verified as ID {self.repo_id}")

    @staticmethod
    def _picked_up(jobs, handle):
        job = next((job for job in jobs if job["handle"] == handle), None)
        if job is None or job["status"] != "running" or job["task_id"] == 0:
            return None
        return job

    def _resolve(self, job, owner):
        """(None, run) for a trusted run, else (reason, run). Lookup failures raise ApiError."""
        if not self.repository_verified:
            self._verify_repository(owner)
        task = self.api.task(self.trust.repo, job["task_id"])
        run = self.api.run_by_number(self.trust.repo, task["run_number"])
        if run.get("commit_sha") != task["head_sha"] or run.get("workflow_id") != task["workflow_id"]:
            return "task and run disagree", run
        reason = trusted_run(run, self.repo_id, owner)
        if reason is None and not self.api.deploy_keys_read_only(self.trust.repo):
            return "repository has a write deploy key", run
        return reason, run

    def _observe_queue(self, seen, inventory_ok):
        for handle in self.pre_start_retries.keys() - seen:
            del self.pre_start_retries[handle]
        data = self.store.data
        changes = {}
        retired = [handle for handle in data["retired"] if handle in seen]
        if retired != data["retired"]:
            changes["retired"] = retired
        refusals = data["refusals"]
        if any(handle not in seen for handle in refusals):
            changes["refusals"] = {handle: budget for handle, budget in refusals.items() if handle in seen}
        # A complete inventory plus a fresh jobs response brackets the window;
        # observed reappearance invalidates earlier evidence.
        now = int(self.wall())
        ambiguous = data["ambiguous"]
        remaining = None
        for handle, intent in ambiguous.items():
            if intent["runners"] is not None:
                continue
            since = intent.get("absent_since")
            if handle in seen:
                if since is None:
                    continue
                replacement = {"name": intent["name"], "runners": None}
            elif not inventory_ok:
                continue
            elif since is None or now < since:
                replacement = intent | {"absent_since": now}
            elif now - since >= INTENT_EXPIRY:
                replacement = None
                log(f"expired registration intent for {intent['name']}: no queued handle or exact runner match")
            else:
                continue
            if remaining is None:
                remaining = ambiguous.copy()
            if replacement is None:
                del remaining[handle]
            else:
                remaining[handle] = replacement
        if remaining is not None:
            changes["ambiguous"] = remaining
            expired = ambiguous.keys() - remaining.keys()
            if expired:
                self.claims.finish(self.store, expired, **changes)
                return
        if changes:
            self.store.save(**changes)

    def _inventory(self):
        try:
            return self.api.runners()
        finally:
            self.inventory_after = self.monotonic() + INVENTORY_POLL

    def _recover_by_name(self, owner):
        ambiguous = self.store.data["ambiguous"]
        unresolved = {intent["name"]: handle for handle, intent in ambiguous.items() if intent["runners"] is None}
        found = {}
        for row in self._inventory():
            if row["name"] in unresolved and row["ephemeral"] and row["owner_id"] == owner and row["repo_id"] == 0:
                found.setdefault(row["name"], []).append({"id": row["id"], "uuid": row["uuid"]})
        if found:
            # Save recovered IDs before DELETE so a crash can replay cleanup by ID.
            recovered = {
                unresolved[name]: {"name": name, "runners": runners} for name, runners in found.items()
            }
            refusals = {handle: budget for handle, budget in self.store.data["refusals"].items() if handle not in recovered}
            self.store.save(ambiguous=ambiguous | recovered, refusals=refusals)
        unmatched = [name for name in unresolved if name not in found]
        if unmatched:
            log(f"{len(unmatched)} unresolved registration(s); no exact runner match for {', '.join(unmatched[:3])}")

    def _delete_recovered(self):
        for handle, intent in self.store.data["ambiguous"].items():
            if intent["runners"] is not None:
                for runner in intent["runners"]:
                    self.api.delete(runner)
                data = self.store.data
                remaining = data["ambiguous"].copy()
                del remaining[handle]
                self.claims.finish(self.store, (handle,), ambiguous=remaining, retired=[*data["retired"], handle])

    def _paused(self):
        for flag in (self.pause, self.host_pause):
            try:
                flag.lstat()
            except FileNotFoundError:
                continue
            except OSError:
                raise SlotError("cannot check the dispatch pause flag; refusing new dispatch") from None
            return True
        return False

    def _dispatch(self, jobs):
        reserved = self.claims.reserve(self.store, jobs)
        if reserved is None:
            return
        job, digest, active = reserved
        handle = active["handle"]
        log(f"registering runner for job {job['id']} attempt {job['attempt']} ({digest})")
        try:
            runner, token = self.api.register(active["name"])
        except HttpError as error:
            # An explicit refusal is not a lost result. Transport failures,
            # 5xx and unreadable success replies may hide a new runner.
            if 300 <= error.status < 500:
                self._record_refusal(handle)
            raise
        active = active | {"runner": runner, "phase": "registered"}
        refusals = self.store.data["refusals"].copy()
        refusals.pop(handle, None)
        self.store.save(active=active, refusals=refusals)
        snapshot = self.slot.observe()
        if snapshot.run is not None or not snapshot.vm_idle or snapshot.residual or not snapshot.again_idle:
            raise SlotError("slot changed during registration; refusing to stage or start")
        self.slot.stage(active["name"], runner["uuid"], token, handle)
        # Queuing is one-way. Even if the client dies or loses the systemd reply,
        # recovery only monitors this intent and never issues its start a second time.
        self.store.save(active=active | {"phase": "start", "queued_at": self.wall()})
        try:
            self.slot.start(active["name"])
        except StartRefused:
            # A known early refusal proves no start was submitted. Record it
            # before cleanup so a restart releases instead of retiring.
            self.store.save(active=active)
            raise
        self.pre_start_retries.pop(handle, None)
        log(f"queued VM start for runner {runner['id']}")

    def _record_refusal(self, handle):
        data = self.store.data
        refusals = data["refusals"].copy()
        retired = data["retired"]
        now = self.wall()
        previous = refusals.get(handle)
        count = 1 if previous is None else min(previous["count"] + 1, REFUSAL_LIMIT)
        first_at = now if previous is None else previous["first_at"]
        retire = count == REFUSAL_LIMIT and now - first_at >= REFUSAL_SPAN
        if retire:
            del refusals[handle]
            retired = [*retired, handle]
        else:
            refusals[handle] = {"count": count, "first_at": first_at}
        self.claims.finish(self.store, (handle,), active=None, retired=retired, refusals=refusals)
        if retire:
            log("retiring handle after repeated registration refusals spanning at least one hour")


def parse_arguments(argv=None):
    """The command line, validated; also configures the slot, forge account and label this process serves."""
    parser = argparse.ArgumentParser(description=__doc__)
    # Every slot setting is required: a dispatcher must never fall back to another slot's identity.
    parser.add_argument("--slot", required=True, help="the slot's microVM name, e.g. ryza-eph-1")
    parser.add_argument("--machine", required=True, help="the slot host's name")
    transport = parser.add_mutually_exclusive_group(required=True)
    transport.add_argument("--slotctl", type=Path, help="the local slot agent")
    transport.add_argument("--ssh-command", type=Path, help="the pinned SSH wrapper for the remote slot agent")
    parser.add_argument("--forge-host", required=True, help="the Forgejo host name, e.g. forge.ugalabugala.org")
    parser.add_argument("--login", required=True, help="the forge account whose runners this registers")
    parser.add_argument("--label", required=True, help="the one runs-on label this slot serves")
    parser.add_argument("--repo-id", type=int, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--claim-states", type=Path, required=True, help="JSON map of slot names to state directories")
    parser.add_argument("--pause-file", type=Path, default=PAUSE_FILE)
    parser.add_argument("--host-pause-file", type=Path, default=HOST_PAUSE_FILE)
    parser.add_argument("--trusted-jobs", action="store_true", help="deliver CI upload credentials to trusted runs")
    parser.add_argument("--repo", help="name of the configured repository under --login (with --trusted-jobs)")
    args = parser.parse_args(argv)
    for path in (args.slotctl or args.ssh_command, args.state_dir, args.claim_states, args.pause_file, args.host_pause_file):
        if not path.is_absolute():
            parser.error("dispatcher paths must be absolute")
    if not positive(args.repo_id):
        parser.error("--repo-id must be positive")
    if args.trusted_jobs != (args.repo is not None):
        parser.error("--trusted-jobs needs --repo, and --repo needs it")
    if args.trusted_jobs and not matches(REPO_NAME, args.repo):
        parser.error("--repo must be a plain repository name")
    # Last, so a refused command line never leaves the process half configured.
    try:
        configure(args.slot, args.machine, args.forge_host, args.login, args.label)
    except ValueError as error:
        parser.error(str(error))
    return args


def claim_states(path, directory):
    try:
        with path.open("rb") as file:
            states = json.load(file)
        if (
            not isinstance(states, dict)
            or not all(matches(SLOT_NAME, slot) and isinstance(value, str) and Path(value).is_absolute()
                       for slot, value in states.items())
            or states.get(SLOT) != str(directory)
            or len(set(states.values())) != len(states)
        ):
            raise ValueError
    except (OSError, ValueError, RecursionError):
        raise StateError("invalid dispatcher claim state map; refusing dispatch") from None
    return {slot: Path(value) for slot, value in states.items()}


def main():
    args = parse_arguments()
    os.umask(0o077)
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    try:
        args.state_dir.mkdir(mode=0o700, exist_ok=True)
        info = args.state_dir.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
            raise StateError("state directory must be root-owned with mode 0700")
        with os.fdopen(
            os.open(args.state_dir / "state.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), "wb"
        ) as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise StateError("another dispatcher holds the state lock") from None
            remote = args.ssh_command is not None
            slot = CommandSlot(
                (str(args.ssh_command or args.slotctl),), lock_fd=None if remote else lock.fileno(), remote=remote,
            )
            store = Store(args.state_dir)
            claims = Claims(CLAIM_ROOT, claim_states(args.claim_states, args.state_dir))
            trust = Trust(args.repo, Path(directory) if directory else None) if args.trusted_jobs else None
            dispatcher = Dispatcher(
                args.repo_id,
                Forgejo(Path(directory) / "forgejo-pat" if directory else None),
                slot,
                store,
                claims,
                pause=args.pause_file,
                host_pause=args.host_pause_file,
                trust=trust,
            )
            # Withdraw previous delivery even if trust is now off. If still on,
            # the new dispatcher must re-resolve trust before delivering again.
            try:
                dispatcher.withdraw()
            except SlotError as error:
                log(error)
                return 1
            while True:
                time.sleep(dispatcher.tick())
    except StateError as error:
        log(error)
    except Exception:
        # Never emit a traceback or an exception constructed from an HTTP payload.
        log("dispatcher stopped unexpectedly; check local slot configuration and durable state")
    return 1


if __name__ == "__main__":
    sys.exit(main())
