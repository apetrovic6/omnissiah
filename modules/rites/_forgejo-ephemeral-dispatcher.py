#!/usr/bin/env python3
"""Dispatch one targeted Forgejo job at a time to Ryza's fixed disposable slot."""

import argparse
from contextlib import closing
import fcntl
import grp
import hashlib
import http.client
import json
import os
import pwd
import re
import secrets
import signal
import stat
import subprocess
import sys
import time
from pathlib import Path

SLOT = "ryza-eph-1"
VM = f"microvm@{SLOT}.service"
SUPPORT = tuple(
    f"microvm-{name}@{SLOT}.service"
    for name in ("tap-interfaces", "macvtap-interfaces", "pci-devices", "virtiofsd", "set-booted")
)
IMAGES = ("nix-store-overlay.img", "var.img")
CREDENTIALS = ("runner-uuid", "runner-token", "job-handle")
HOST = "forge.ugalabugala.org"
RUNNERS = "/user/actions/runners"
LOGIN = "manjo"
LABEL = "nix-eph"
POLL = 7
BUSY_POLL_FAST = 15
BUSY_FAST_WINDOW = 5 * 60
BUSY_POLL = 60
INVENTORY_POLL = 5 * 60
INTENT_EXPIRY = 24 * 60 * 60
REFUSAL_LIMIT = 3
REFUSAL_SPAN = 60 * 60
PAUSE_FILE = Path("/run/forgejo-ephemeral-dispatcher/pause")
REQUEST_TIMEOUT = 10
MAX_RESPONSE = 2 * 1024 * 1024
VM_DEADLINE = 90 + 75 * 60 + 30  # Informational only; systemd enforces the actual deadlines.
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
NAME = re.compile(r"eph-[0-9a-f]{12}-ryza-[0-9a-f]{32}")
TOKEN = re.compile(r"[!-~]{1,4096}")
UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")


class ApiError(Exception):
    """Only fixed labels and HTTP status may be included in API diagnostics."""


class HttpError(ApiError):
    def __init__(self, operation, status):
        self.status = status
        hint = "; verify the manjo PAT and write:user scope" if status in (401, 403) else ""
        super().__init__(f"Forgejo {operation}: HTTP {status}{hint}")


class SlotError(Exception):
    """A safe diagnostic for a slot that cannot be reused yet."""


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

    def _request(self, operation, method, path, accepted, payload=None):
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
                    data = response.read(MAX_RESPONSE + 1)
                    if len(data) > MAX_RESPONSE:
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
            raise ApiError("Forgejo identity is not the expected manjo account; check the PAT")
        if expected is not None and user["id"] != expected:
            raise ApiError("Forgejo manjo account ID changed; reconcile ownership before restarting")
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


class Systemctl:
    def __init__(self, run=subprocess.run, lock_fd=None):
        self.run = run
        self.lock_fds = () if lock_fd is None else (lock_fd,)

    def _call(self, action, *units, options=()):
        try:
            result = self.run(
                ("systemctl", "--system", "--no-pager", *options, action, *units),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                # If we die while systemctl is still alive, its copy keeps the lock
                # held until the next dispatcher can safely reconcile.
                pass_fds=self.lock_fds,
                timeout=10,
                check=True,
            )
        except (OSError, subprocess.SubprocessError):
            raise SlotError(f"systemctl {action} failed or timed out for {SLOT}; reconciling unit state") from None
        return result.stdout

    def observe(self, unit):
        # One GetAll via systemctl show: checking ActiveState and list-jobs separately
        # permits an already-queued start to run between the two queries.
        output = self._call("show", unit, options=("--all", "--property=LoadState,ActiveState,Job,Result"))
        try:
            props = dict(line.split("=", 1) for line in output.decode("ascii").splitlines())
            active, job, result = props["ActiveState"], props["Job"], props["Result"]
            if props["LoadState"] != "loaded" or (job and not re.fullmatch(r"[0-9]{1,10}", job)):
                raise ValueError
            if result not in ("success", "timeout", "exit-code", "signal", "core-dump", "resources", "start-limit-hit"):
                result = "other result"
            if active in ("inactive", "failed"):
                return (not job or int(job) == 0), result
            if active in ("active", "activating", "deactivating", "reloading", "refreshing"):
                return False, result
        except (KeyError, ValueError):
            pass
        raise SlotError(f"unknown systemd state for {unit}; refusing slot reuse")

    def idle(self, unit):
        return self.observe(unit)[0]

    def start(self):
        self._call("start", VM, options=("--no-block", "--job-mode=fail"))

    def stop(self):
        self._call("stop", VM, options=("--no-block",))

    def stop_support(self, units):
        self._call("stop", *units, options=("--no-block",))


def unlink_files(directory, names, *, remove_dir=False):
    try:
        fd = os.open(directory, DIR_FLAGS)
    except FileNotFoundError:
        return
    failure = None
    try:
        for name in names:
            try:
                os.unlink(name, dir_fd=fd)
            except FileNotFoundError:
                pass
            except OSError as error:
                failure = error
    finally:
        os.close(fd)
    if failure is not None:
        raise failure
    if remove_dir:
        directory.rmdir()


class SlotFiles:
    def __init__(self, vm_dir, credentials, uid, gid):
        self.vm_dir = vm_dir
        self.credentials = credentials
        self.staging = credentials.with_name(f".{credentials.name}.staging")
        self.uid, self.gid = uid, gid

    def scrub(self):
        failed = False
        for directory, names, remove in (
            (self.vm_dir, IMAGES, False),
            (self.credentials, CREDENTIALS, True),
            (self.staging, CREDENTIALS, True),
        ):
            try:
                unlink_files(directory, names, remove_dir=remove)
            except OSError:
                failed = True
        if failed:
            raise SlotError("cannot scrub exact slot images or credentials; check slot paths for unexpected files")

    def stage(self, runner_uuid, token, handle):
        if not matches(TOKEN, token):
            raise ApiError("Forgejo register runner: missing or invalid runner token")
        try:
            self.staging.mkdir(mode=0o700)
            for name, value in zip(CREDENTIALS, (runner_uuid, token, handle), strict=True):
                fd = os.open(self.staging / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
                with os.fdopen(fd, "wb") as file:
                    os.fchown(file.fileno(), self.uid, self.gid)
                    file.write(value.encode())
            os.chown(self.staging, self.uid, self.gid)
            self.staging.rename(self.credentials)
        except OSError:
            raise SlotError("cannot stage runner credentials; check ownership and permissions of the credential parent") from None


class Store:
    def __init__(self, directory):
        self.directory = directory
        try:
            with (directory / "state.json").open("rb") as file:
                self.data = json.load(file)
        except FileNotFoundError:
            self.data = {
                "version": 2, "slot": SLOT, "owner_id": None, "active": None,
                "ambiguous": {}, "retired": [], "refusals": {},
            }
            return
        except (OSError, ValueError, RecursionError):
            raise StateError("cannot read state.json; reconcile persisted state before restarting") from None
        if not self._valid(self.data):
            raise StateError("invalid state.json; reconcile persisted state before restarting")

    @staticmethod
    def _valid(data):
        if (
            not isinstance(data, dict)
            or data.keys() != {"version", "slot", "owner_id", "active", "ambiguous", "retired", "refusals"}
            or not positive(data["version"])
            or data["version"] != 2
            or data["slot"] != SLOT
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
                or not matches(NAME, intent["name"])
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
            or not matches(NAME, active["name"])
            or active["phase"] not in ("intent", "registered", "start", "cleanup")
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


class Dispatcher:
    def __init__(self, repo_id, api, system, files, store, monotonic=time.monotonic, wall=time.time, pause=PAUSE_FILE):
        self.repo_id, self.api, self.system, self.files, self.store = repo_id, api, system, files, store
        self.monotonic, self.wall = monotonic, wall
        self.pause = pause
        self.api_after = self.api_delay = 0
        self.inventory_after = self.busy_after = 0
        self.busy_misses = 0
        self.observed = None
        self.identity_verified = False
        self.deadline_logged = False

    def tick(self):
        idle = True
        try:
            idle = self._local()
            now = self.monotonic()
            if not idle:
                if now >= self.busy_after:
                    queued_at = self.store.data["active"]["queued_at"]
                    interval = BUSY_POLL_FAST if self.wall() - queued_at < BUSY_FAST_WINDOW else BUSY_POLL
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
        if not self.system.idle(VM):
            if active is None or active["phase"] != "start":
                raise SlotError("VM is live or has a pending job without a recorded start; refusing slot reuse")
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
        residual = [unit for unit in SUPPORT if not self.system.idle(unit)]
        if residual:
            if self.system.idle(VM):
                self.system.stop_support(residual)
            raise SlotError("waiting for slot support units to stop")
        # Re-observe after inspecting support units, also before any destructive cleanup.
        idle, result = self.system.observe(VM)
        if not idle:
            raise SlotError("VM state changed during reconciliation; waiting before slot cleanup")
        self.files.scrub()
        if active is None or active["phase"] == "cleanup":
            return True
        if active["phase"] == "intent":
            ambiguous = self.store.data["ambiguous"] | {active["handle"]: {"name": active["name"], "runners": None}}
            self.store.save(active=None, ambiguous=ambiguous)
            log(f"registration outcome unresolved for {active['name']}; searching owned runners by exact name")
        else:
            cleanup = active | {"phase": "cleanup", "queued_at": None}
            self.store.save(active=cleanup)
            log(f"VM idle ({result}); local files scrubbed for runner {active['runner']['id']}")
        return True

    def _remote(self, idle):
        data = self.store.data
        owner = self.api.identify(data["owner_id"])
        if not self.identity_verified:
            log("Forgejo PAT identity verified as manjo")
            self.identity_verified = True
        if data["owner_id"] is None:
            if self.monotonic() < self.inventory_after:
                return
            if any(row["owner_id"] == owner and matches(NAME, row["name"]) for row in self._inventory()):
                raise ApiError("state.json absent but a dispatcher-named runner exists; reconcile before enabling dispatch")
            self.store.save(owner_id=owner)
        if idle and data["active"] is not None:
            active = data["active"]
            self.api.delete(active["runner"])
            self.store.save(active=None, retired=[*data["retired"], active["handle"]])
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
            return
        data = self.store.data
        blocked = set(data["retired"]) | data["ambiguous"].keys()
        job = min(
            (
                job for job in jobs
                if job["status"] == "waiting" and job["task_id"] == 0
                and job["runs_on"] == [LABEL] and job["handle"] not in blocked
            ),
            key=lambda job: job["id"],
            default=None,
        )
        if job is not None and not self._paused():
            self._dispatch(job)

    def _check_cancelled(self, seen):
        active = self.store.data["active"]
        if active["handle"] in seen:
            self.busy_misses = 0
        else:
            self.busy_misses += 1
            if self.busy_misses >= 2 and not self.system.idle(VM):
                self.system.stop()
                log(f"queued VM stop: runner {active['runner']['id']} target absent from consecutive job polls")

    def _observe_queue(self, seen, inventory_ok):
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
                self.store.save(ambiguous=remaining, retired=[*data["retired"], handle])

    def _paused(self):
        try:
            self.pause.lstat()
        except FileNotFoundError:
            return False
        except OSError:
            raise SlotError("cannot check the dispatch pause flag; refusing new dispatch") from None
        return True

    def _dispatch(self, job):
        handle = job["handle"]
        digest = hashlib.sha256(handle.encode()).hexdigest()[:12]
        active = dict(handle=handle, name=f"eph-{digest}-ryza-{secrets.token_hex(16)}", runner=None, phase="intent", queued_at=None)
        self.store.save(active=active)
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
        if any(not self.system.idle(unit) for unit in SUPPORT) or not self.system.idle(VM):
            raise SlotError("slot changed during registration; refusing to stage or start")
        self.files.stage(runner["uuid"], token, handle)
        # Queuing is one-way. Even if the client dies or loses the systemd reply,
        # recovery only monitors this intent and never issues its start a second time.
        self.store.save(active=active | {"phase": "start", "queued_at": self.wall()})
        self.system.start()
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
        self.store.save(active=None, retired=retired, refusals=refusals)
        if retire:
            log("retiring handle after repeated registration refusals spanning at least one hour")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-id", type=int, required=True)
    for name in ("--state-dir", "--vm-dir", "--credential-dir"):
        parser.add_argument(name, type=Path, required=True)
    args = parser.parse_args()
    if not positive(args.repo_id):
        parser.error("--repo-id must be positive")
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
            files = SlotFiles(
                args.vm_dir, args.credential_dir, pwd.getpwnam("microvm-eph").pw_uid, grp.getgrnam("microvm-eph").gr_gid
            )
            dispatcher = Dispatcher(
                args.repo_id,
                Forgejo(Path(directory) / "forgejo-pat" if directory else None),
                Systemctl(lock_fd=lock.fileno()),
                files,
                Store(args.state_dir),
            )
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
