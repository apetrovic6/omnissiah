#!/usr/bin/env python3
"""Dispatch one targeted Forgejo job at a time to one fixed disposable slot (--slot).

Every boot is untrusted. With --trusted-jobs, a picked-up job in a pool's trust allowlist is mapped exactly:
job task_id -> repository task -> run_number -> run. Only then can the dispatcher deliver the CI signing key
and ncps netrc to the slot's root-only trust share. Any doubt means nothing is delivered. With --trusted-egress,
only after a successful delivery, the slot host also moves the run's HTTPS to the guard onto its second SNAT
source (slotctl `egress trusted`); withdraw, scrub and the VM's stop end it.

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

# One process serves one slot. The forge and queue belong to each pool, not to the process.
SLOT = "ryza-eph-1"
MACHINE = "ryza"
VM = f"microvm@{SLOT}.service"
SUPPORT_UNITS = ("tap-interfaces", "macvtap-interfaces", "pci-devices", "virtiofsd", "set-booted")
SUPPORT = tuple(f"microvm-{name}@{SLOT}.service" for name in SUPPORT_UNITS)
FORGES = {"ugalabugala": "forge.ugalabugala.org", "noosphere": "forge.noosphere.uk"}
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
START_MAX_BACKOFF = 10 * 60
START_ESCALATE = 5
PAUSE_FILE = Path("/run/forgejo-ephemeral-dispatcher/pause")
HOST_PAUSE_FILE = Path("/run/forgejo-ephemeral/pause")
CLAIM_ROOT = Path("/run/forgejo-ephemeral/claims")
REQUEST_TIMEOUT = 10
MAX_RESPONSE = 2 * 1024 * 1024
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
# All configured names used in paths, runner names or query strings must be plain components.
SLOT_NAME = re.compile(r"[a-z][a-z0-9-]{0,62}")
LOGIN_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,39}")
LABEL_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")


def runner_namespace(slot):
    # Keep recognizing the Ryza pilot's durable registrations after the unit rename.
    return "ryza" if slot == "ryza-eph-1" else slot


def runner_pattern(slot):
    return re.compile(rf"eph-[0-9a-f]{{12}}-{re.escape(runner_namespace(slot))}-[0-9a-f]{{32}}")


NAME = runner_pattern(SLOT)


def configure(slot, machine):
    """Point this process at one slot on one machine."""
    for name, pattern, value in (
        ("slot", SLOT_NAME, slot),
        ("machine", SLOT_NAME, machine),
    ):
        if not isinstance(value, str) or pattern.fullmatch(value) is None:
            raise ValueError(f"invalid {name}")
    global SLOT, MACHINE, VM, SUPPORT, NAME
    SLOT, MACHINE = slot, machine
    VM = f"microvm@{SLOT}.service"
    SUPPORT = tuple(f"microvm-{name}@{SLOT}.service" for name in SUPPORT_UNITS)
    NAME = runner_pattern(SLOT)


class Pool:
    """Trusted local config for one Forgejo owner queue. Queue identity does not depend on its display name."""

    def __init__(self, name, *, forge, host, login, scope, labels, dispatch, maxSlots, trust):
        if (
            not matches(SLOT_NAME, name) or not isinstance(forge, str) or FORGES.get(forge) != host
            or not isinstance(host, str) or not matches(LOGIN_NAME, login)
            or not isinstance(scope, dict) or len(scope) != 1
            or not isinstance(labels, list) or not labels or not all(matches(LABEL_NAME, label) for label in labels)
            or len(set(labels)) != len(labels)
            or not (dispatch == "owner" or isinstance(dispatch, list) and dispatch and all(map(positive, dispatch)))
            or not positive(maxSlots)
            or not isinstance(trust, dict) or trust.keys() != {"repos", "users"}
            or not isinstance(trust["repos"], dict) or not isinstance(trust["users"], list)
            or not all(matches(LOGIN_NAME, user) for user in trust["users"])
        ):
            raise ValueError
        kind, owner = next(iter(scope.items()))
        if (
            kind not in ("user", "org") or not matches(LOGIN_NAME, owner)
            or (kind == "user" and owner.lower() != login.lower())
        ):
            raise ValueError
        repos = {}
        for repo_id, repo in trust["repos"].items():
            if (
                not matches(re.compile(r"[1-9][0-9]*"), repo_id)
                or not isinstance(repo, dict) or repo.keys() != {"owner", "name", "schedules"}
                or not matches(LOGIN_NAME, repo["owner"]) or repo["owner"].lower() != owner.lower()
                or not matches(REPO_NAME, repo["name"]) or repo["name"] in (".", "..")
                or type(repo["schedules"]) is not bool
                or (dispatch != "owner" and int(repo_id) not in dispatch)
            ):
                raise ValueError
            repos[int(repo_id)] = repo
        # An allowlisted repo with nobody allowed would still trust every writer through its schedules.
        if repos and not trust["users"]:
            raise ValueError
        self.name, self.forge, self.host, self.login = name, forge, host, login.lower()
        self.owner, self.kind = owner.lower(), kind
        self.labels = frozenset(labels)
        self.repos = None if dispatch == "owner" else frozenset(dispatch)
        self.max_slots = maxSlots
        self.trust_repos, self.trust_users = repos, frozenset(user.lower() for user in trust["users"])
        scope_path = "/user" if kind == "user" else f"/orgs/{self.owner}"
        self.runners_path = f"{scope_path}/actions/runners"
        self.jobs_path = f"{self.runners_path}/jobs?labels={','.join(labels)}"
        self.url = f"https://{host}"
        pilot = (forge, kind, self.owner) == ("ugalabugala", "user", "manjo")
        self.key = f"{host}:{self.owner}" if pilot else f"{host}:{kind}:{self.owner}"
        self.state_file = "state.json" if pilot else f"pool-{self.key}.json"


class ApiError(Exception):
    """Only fixed labels and HTTP status may be included in API diagnostics."""


class HttpError(ApiError):
    def __init__(self, operation, status):
        self.status = status
        hint = "; verify the PAT and its write:user, write:organization (org pools), and read:repository (trust) scopes" if status in (401, 403) else ""
        super().__init__(f"Forgejo {operation}: HTTP {status}{hint}")


class SlotError(Exception):
    """A safe diagnostic for a slot that cannot be reused yet."""


class StartRefused(SlotError):
    """slotctl explicitly refused before asking systemd to queue a start."""


class EgressRefused(SlotError):
    """The slot host will not use its trusted source for this run (it may belong to another host)."""


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


def log(message, pool=None):
    prefix = f"[{pool.name}] " if pool is not None else ""
    print(f"{SLOT}: {prefix}{message}", file=sys.stderr, flush=True)


def expired(_signum, _frame):
    raise TimeoutError


class Forgejo:
    def __init__(self, pool, pat_file, connect=None):
        self.pool, self.pat_file = pool, pat_file
        self.pat = self.deadline = None
        # Direct connections only: no environment proxy, redirects or URL-valued inputs.
        self.connect = connect or (lambda: http.client.HTTPSConnection(pool.host, timeout=REQUEST_TIMEOUT))

    def _authorization(self):
        if self.pat is None:
            try:
                with self.pat_file.open("rb") as file:
                    pat = file.read(4097).strip()
            except (AttributeError, OSError):
                raise ApiError(f"host forgejo-pat-{self.pool.forge} credential is unavailable; check LoadCredential") from None
            if not re.fullmatch(rb"[!-~]{1,4096}", pat):
                raise ApiError(f"host forgejo-pat-{self.pool.forge} credential is empty or invalid")
            self.pat = pat.decode("ascii")
        return "token " + self.pat

    @contextmanager
    def within(self, seconds):
        previous = self.deadline
        deadline = time.monotonic() + seconds
        self.deadline = deadline if previous is None else min(deadline, previous)
        try:
            yield
        finally:
            self.deadline = previous

    def _request(self, operation, method, path, accepted, payload=None, limit=MAX_RESPONSE):
        headers = {"Authorization": self._authorization(), "Accept": "application/json"}
        body = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode()
        timeout = REQUEST_TIMEOUT
        if self.deadline is not None:
            timeout = min(timeout, self.deadline - time.monotonic())
            if timeout <= 0:
                raise ApiError("Forgejo request deadline reached")
        # A socket timeout alone permits an arbitrarily slow trickle of response bytes.
        previous = signal.signal(signal.SIGALRM, expired)
        signal.setitimer(signal.ITIMER_REAL, timeout)
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
        pool = self.pool
        user, _ = self._request("identity", "GET", "/user", (200,))
        login = user.get("login") if isinstance(user, dict) else None
        if not matches(LOGIN_NAME, login) or login.lower() != pool.login or not positive(user.get("id")):
            raise ApiError(f"Forgejo identity is not the expected {pool.login} account; check the PAT")
        owner = account = user["id"]
        if pool.kind == "org":
            org, _ = self._request("organization identity", "GET", f"/orgs/{pool.owner}", (200,))
            name = org.get("name") if isinstance(org, dict) else None
            if not matches(LOGIN_NAME, name) or name.lower() != pool.owner or not positive(org.get("id")) or org["id"] == account:
                raise ApiError(f"Forgejo organization identity is not {pool.owner}")
            owner = org["id"]
        if expected is not None and owner != expected:
            identity = f"{pool.login} account" if pool.kind == "user" else f"{pool.owner} organization"
            raise ApiError(f"Forgejo {identity} ID changed; reconcile ownership before restarting")
        return owner, account

    def jobs(self, owner):
        rows, _ = self._request("jobs", "GET", self.pool.jobs_path, (200,))
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
            if self.pool.repos is None or row["repo_id"] in self.pool.repos:
                jobs.append(row)
        return jobs

    def runners(self):
        """Read all pages before deleting, so our deletes cannot move rows between pages."""
        rows = {}
        expected_total = None
        for page in range(1, 101):
            batch, headers = self._request(
                "list owned runners", "GET", f"{self.pool.runners_path}?visible=false&page={page}&limit=50", (200,)
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
        result, _ = self._request("register runner", "POST", self.pool.runners_path, (201,), {"name": name, "ephemeral": True})
        if not isinstance(result, dict):
            raise ApiError("Forgejo register runner: invalid registration response")
        runner = {key: result.get(key) for key in ("id", "uuid")}
        if not runner_id_ok(runner):
            raise ApiError("Forgejo register runner: invalid ID or UUID; reconciling by name")
        return runner, result.get("token")

    def delete(self, runner):
        status, _ = self._request("delete runner", "DELETE", f"{self.pool.runners_path}/{runner['id']}", (204, 404))
        log(f"runner {runner['id']} cleanup: HTTP {status}", self.pool)

    # The /repos routes need the PAT's read:repository scope (Forgejo v15.0.12 routers/api/v1/api.go:1075-1076).

    def repository(self, path, repo_id, owner):
        repo, _ = self._request("repository", "GET", path, (200,))
        metadata = repo.get("owner") if isinstance(repo, dict) else None
        login = metadata.get("login") if isinstance(metadata, dict) else None
        if (
            not isinstance(repo, dict)
            or repo.get("id") != repo_id
            or not matches(LOGIN_NAME, login) or login.lower() != self.pool.owner
            or metadata.get("id") != owner
        ):
            raise ApiError(f"Forgejo repository: {path} does not match the configured repository ID and owner")
        if type(repo.get("mirror")) is not bool:
            raise ApiError("Forgejo repository: unexpected repository metadata")
        return repo

    def user(self, login):
        """A trust user's account ID (GET /users/{login}, user scope). A renamed account answers 307: not followed."""
        user, _ = self._request("trust user", "GET", f"/users/{login}", (200,))
        name = user.get("login") if isinstance(user, dict) else None
        if not matches(LOGIN_NAME, name) or name.lower() != login or not positive(user.get("id")):
            raise ApiError("Forgejo trust user: unexpected account metadata")
        return user["id"]

    def _access_rows(self, operation, path):
        seen, total = set(), None
        for page in range(1, 21):
            rows, headers = self._request(operation, "GET", f"{path}?page={page}&limit=50", (200,))
            count = headers.get("X-Total-Count", "")
            if not isinstance(rows, list) or not re.fullmatch(r"[0-9]{1,6}", count):
                raise ApiError(f"Forgejo {operation}: invalid access list or pagination")
            if total is not None and int(count) != total:
                raise ApiError(f"Forgejo {operation}: list changed during pagination")
            total = int(count)
            for row in rows:
                if not isinstance(row, dict) or not positive(row.get("id")) or row["id"] in seen:
                    raise ApiError(f"Forgejo {operation}: invalid or duplicate account")
                seen.add(row["id"])
                yield row
            if len(seen) == total:
                return
            if not rows or len(seen) > total:
                raise ApiError(f"Forgejo {operation}: inconsistent pagination")
        raise ApiError(f"Forgejo {operation}: access list exceeds 20 pages")

    def writer_gap(self, path, trust_ids):
        """Check actual access: Forgejo hides stale team allowlist entries in branch protections."""
        def login_for(operation, row):
            login = row.get("login")
            if not matches(LOGIN_NAME, login):
                raise ApiError(f"Forgejo {operation}: invalid account login")
            return login.lower()

        for row in self._access_rows("collaborators", f"{path}/collaborators"):
            login = login_for("collaborators", row)
            body, _ = self._request(
                "collaborator permission", "GET", f"{path}/collaborators/{login}/permission", (200,)
            )
            permission = body.get("permission") if isinstance(body, dict) else None
            user = body.get("user") if isinstance(body, dict) else None
            if (
                permission not in ("none", "read", "write", "admin", "owner") or not isinstance(user, dict)
                or not positive(user.get("id")) or user["id"] != row["id"]
                or login_for("collaborator permission", user) != login
            ):
                raise ApiError("Forgejo collaborator permission: unexpected access mode or account")
            if permission in ("write", "admin", "owner") and trust_ids.get(login) != row["id"]:
                return "repository has a write or admin collaborator outside trust.users"
        if self.pool.kind == "org":
            teams, _ = self._request("repository teams", "GET", f"{path}/teams", (200,))
            if not isinstance(teams, list) or not teams:
                raise ApiError("Forgejo repository teams: missing organization teams")
            seen = set()
            for team in teams:
                if not isinstance(team, dict) or not positive(team.get("id")) or team["id"] in seen:
                    raise ApiError("Forgejo repository teams: invalid or duplicate team")
                team_id = team["id"]
                seen.add(team_id)
                for row in self._access_rows("team members", f"/teams/{team_id}/members"):
                    if trust_ids.get(login_for("team members", row)) != row["id"]:
                        return "repository team has a member outside trust.users"
        return None

    def branch_protections(self, path):
        """All branch protection rules (GET /repos/{o}/{r}/branch_protections: one unpaginated list).

        The route needs read:repository and repository admin access (routers/api/v1/api.go:864-872).
        """
        rules, _ = self._request("branch protections", "GET", f"{path}/branch_protections", (200,))
        if rules is None:  # Forgejo serializes the empty result as a nil slice.
            return []
        if not isinstance(rules, list) or any(not isinstance(rule, dict) for rule in rules):
            raise ApiError("Forgejo branch protections: unexpected response")
        return rules

    def task(self, path, task_id):
        """The task a runner created for a job. Tasks are listed newest first (`id` DESC)."""
        for page in range(1, TASK_PAGES + 1):
            body, _ = self._request("tasks", "GET", f"{path}/actions/tasks?status=running&page={page}&limit=50", (200,))
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

    def deploy_keys_read_only(self, path):
        """True only if every deploy key on the repository is read-only (GET /repos/{o}/{r}/keys, all pages).

        Forgejo attributes a deploy-key push to the repository owner (routers/private/serv.go:266-270), so a
        write deploy key could impersonate a trusted user. The route needs read:repository and repository admin access.
        """
        seen, total = set(), None
        for page in range(1, 21):
            rows, headers = self._request("deploy keys", "GET", f"{path}/keys?page={page}&limit=50", (200,))
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

    def run_by_number(self, path, number):
        """The run whose per-repository index is `number`: unique per repository."""
        body, _ = self._request(
            "runs", "GET", f"{path}/actions/runs?run_number={number}&limit=50", (200,),
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


def trusted_run(run, repo_id, owner, pool, trust_ids):
    """None when the run is trusted, else a fixed reason. Fields are server-set; nothing the job controls.

    trust_ids maps configured logins to account IDs pinned at startup.

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
    - Any default-branch push, by anyone, re-creates the repository's schedules with the forgejo-actions user as
      trigger (notifier_helper.go:542-627). A schedule therefore says nothing about who wrote it, so schedule
      trust is a per-repository opt-in (trust.repos.<id>.schedules) and relies on protection_gap.
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
    if repository["id"] != repo_id or repo_owner["id"] != owner or repo_owner["login"].lower() != pool.owner:
        return "repository mismatch"
    if run["is_fork_pull_request"]:
        return "fork or AGit pull request"
    if run["need_approval"]:
        return "awaiting approval"
    on_default = run["prettyref"] == repository["default_branch"]
    login = user.get("login")
    pinned = trust_ids.get(login.lower()) if matches(LOGIN_NAME, login) else None
    denied = None if user["id"] == pinned else "not in the trust allowlist" if pinned is None else (
        "ID differs from the pinned trust user; reconcile the account before trusting it"
    )
    if event == "push" and trigger_event == "push":
        if schedule != 0:
            return "push run carries a schedule"
        if denied:
            return f"push user {denied}"
        return None if on_default else "push not on the default branch"
    if trigger_event == "schedule" and event in ("push", "schedule"):
        if schedule <= 0:
            return "schedule run without a schedule"
        if user["id"] != ACTIONS_USER:
            return "schedule not triggered by forgejo-actions"
        if not on_default:
            return "schedule not on the default branch"
        return None if pool.trust_repos[repo_id]["schedules"] else "schedule trust not enabled for this repository"
    if event == "workflow_dispatch" and trigger_event == "workflow_dispatch":
        if denied:
            return f"dispatch user {denied}"
        # Any ref git resolves is accepted: refs/pull/N/head ("#N"), "pull/5/head", a SHA, another branch or a tag.
        return None if on_default else "dispatch not on the default branch"
    return "event is not push, schedule or workflow_dispatch"


GLOB_SPECIAL = set("*?[]{}\\!")


def protection_gap(rules, branch, users):
    """None if only trust.users can change the default branch, else a fixed reason. Malformed rules raise ApiError.

    Forgejo v15.0.12 applies the first matching rule, exact names before globs (models/git/protected_branch_list.go
    sort, GetFirstMatched; exact names compare case-insensitively). Only an exact-name rule for the default branch
    is accepted, so no glob semantics are emulated here. Writes to a protected branch (routers/private/
    hook_pre_receive.go:360-490) are a direct push, allowed by CanUserPush (no admin bypass), or a PR merge, allowed
    by IsUserMergeWhitelisted, which falls back to plain write access without a merge allowlist. A push that only
    touches unprotected_file_patterns skips the push allowlist. Write deploy keys are refused separately.
    Whitelist names list only accounts and teams that currently have read access (services/convert/convert.go
    ToBranchProtection), which is the set that can write today.
    """
    matched = []
    for rule in rules:
        name = rule.get("rule_name")
        if not isinstance(name, str):
            raise ApiError("Forgejo branch protections: unexpected rule metadata")
        if not GLOB_SPECIAL.intersection(name) and name.casefold() == branch.casefold():
            matched.append(rule)
    if len(matched) != 1:
        return "default branch has no single branch protection rule of its own"
    rule = matched[0]
    try:
        push, push_list = rule["enable_push"], rule["enable_push_whitelist"]
        merge_list, unprotected = rule["enable_merge_whitelist"], rule["unprotected_file_patterns"]
        lists = [rule[key] for key in (
            "merge_whitelist_usernames", "merge_whitelist_teams", "push_whitelist_usernames", "push_whitelist_teams"
        )]
        if not (
            all(type(flag) is bool for flag in (push, push_list, merge_list))
            and isinstance(unprotected, str)
            and all(isinstance(names, list) and all(isinstance(name, str) for name in names) for names in lists)
        ):
            raise TypeError
    except (KeyError, TypeError):
        raise ApiError("Forgejo branch protections: unexpected rule metadata") from None
    # With pushes off, CanUserPush refuses everyone before it reads the push allowlist.
    names = lists[0] + (lists[2] if push else [])
    teams = lists[1] + (lists[3] if push else [])
    if push and not push_list:
        return "default branch protection lets every writer push"
    if not merge_list:
        return "default branch protection lets every writer merge"
    if unprotected.strip():
        return "default branch protection has unprotected file patterns"
    if teams:
        return "default branch protection allows a team"
    if any(name.lower() not in users for name in names):
        return "default branch protection allows a user outside trust.users"
    return None


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
        "stop-support": "stop", "scrub": "show", "deliver": "show", "egress": "start",
    }
    REFUSALS = {
        "watchdog-arm-failed": "could not arm the slot watchdog; no VM start was submitted",
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
        "no-trusted-egress": "this slot host has no trusted egress source; check egress.trusted on both ends",
        "egress-not-delivered": "CI credentials are not in the trust share; not using the trusted egress source",
        "egress-address-conflict": "another host answers ARP for the trusted egress address; the slot host won't take it",
        "egress-address-missing": "the trusted egress address is not on the slot host's uplink (dropped on a conflict?)",
        "egress-failed": "cannot start trusted egress; check the slot host's egress unit",
        "egress-stop-failed": "cannot stop trusted egress; check the slot host's egress unit and NAT rules",
    }
    # Refusals that hold for the rest of a run: retrying would only probe the address again.
    EGRESS_REFUSALS = frozenset((b"egress-address-conflict", b"egress-address-missing"))
    # These gates run before VM start submission. A generic systemctl
    # failure, by contrast, can mean the reply to a queued start was lost.
    START_REFUSALS = frozenset((
        b"slot-busy", b"slot-lock", b"slot-user-missing", b"run-marker", b"run-mismatch",
        b"disk-space-check", b"disk-space-low", b"remote-launch", b"watchdog-arm-failed",
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
                timeout=120 if self.remote else self.TIMEOUTS.get(verb, 40),
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
            if message is not None and verb == "egress" and result.stderr.removesuffix(b"\n") in self.EGRESS_REFUSALS:
                raise EgressRefused(message)
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

    def stage(self, run, runner_uuid, token, handle, url, label):
        if not matches(TOKEN, token):
            raise ApiError("Forgejo register runner: missing or invalid runner token")
        self._call("stage", run, payload={"uuid": runner_uuid, "token": token, "handle": handle, "url": url, "label": label})

    def scrub(self, run):
        self._call("scrub", run if run is not None else NO_RUN)

    def deliver(self, run, secrets):
        self._call("deliver", run, payload={name: base64.b64encode(secrets[name]).decode("ascii") for name in TRUST_FILES})

    def withdraw(self, run):
        """Also stops the slot's trusted egress, if its host has one."""
        self._call("withdraw", run if run is not None else NO_RUN)

    def egress_trusted(self, run):
        self._call("egress", "trusted", run)



class Store:
    def __init__(self, directory, state_file, *, slot=None):
        self.directory, self.state_file = directory, state_file
        slot = SLOT if slot is None else slot
        try:
            with (directory / state_file).open("rb") as file:
                self.data = json.load(file)
        except FileNotFoundError:
            self.data = {
                "version": 2, "slot": slot, "owner_id": None, "active": None,
                "ambiguous": {}, "retired": [], "refusals": {},
            }
            return
        except (OSError, ValueError, RecursionError):
            raise StateError(f"cannot read {state_file}; reconcile persisted state before restarting") from None
        if not self._valid(self.data, slot):
            raise StateError(f"invalid {state_file}; reconcile persisted state before restarting")

    @staticmethod
    def _valid(data, slot):
        name = runner_pattern(slot)
        if (
            not isinstance(data, dict)
            or data.keys() - {"trust_ids", "unpicked"} != {"version", "slot", "owner_id", "active", "ambiguous", "retired", "refusals"}
            or not positive(data["version"])
            or data["version"] != 2
            or data["slot"] != slot
            or not positive(data["owner_id"])
            or not isinstance(data["retired"], list)
            or not all(handle_ok(handle) for handle in data["retired"])
            or not isinstance(data["ambiguous"], dict)
            or not isinstance(data["refusals"], dict)
            or not isinstance(data.get("trust_ids", {}), dict)
            or not all(
                matches(LOGIN_NAME, login) and login == login.lower() and positive(value)
                for login, value in data.get("trust_ids", {}).items()
            )
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
        unpicked = data.get("unpicked", {})
        if not isinstance(unpicked, dict) or any(
            not handle_ok(handle) or not positive(count) or count >= REFUSAL_LIMIT
            for handle, count in unpicked.items()
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
            or active.keys() - {"picked_up_at", "trusted", "revalidate_by"} != {"handle", "name", "runner", "phase", "queued_at"}
            or not handle_ok(active["handle"])
            or not matches(name, active["name"])
            or active["phase"] not in ("intent", "registered", "start", "cleanup", "release")
            or ("picked_up_at" in active and (active["phase"] != "start" or not timestamp(active["picked_up_at"])))
        ):
            return False
        if "trusted" in active:
            proof = active["trusted"]
            if (
                "picked_up_at" not in active
                or not isinstance(proof, dict) or proof.keys() != {"task_id", "run_id"}
                or not positive(proof["task_id"]) or not positive(proof["run_id"])
            ):
                return False
        if "revalidate_by" in active and ("trusted" not in active or not timestamp(active["revalidate_by"])):
            return False
        if active["phase"] == "intent":
            return active["runner"] is None and active["queued_at"] is None
        return runner_id_ok(active["runner"]) and (
            timestamp(active["queued_at"]) if active["phase"] == "start" else active["queued_at"] is None
        )

    def save(self, **changes):
        data = self.data | changes
        if not data.get("unpicked"):
            data.pop("unpicked", None)
        try:
            directory = os.open(self.directory, DIR_FLAGS)
            try:
                temporary = f"{self.state_file}.tmp"
                fd = os.open(
                    temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600, dir_fd=directory
                )
                with os.fdopen(fd, "w") as file:
                    json.dump(data, file, separators=(",", ":"))
                    file.flush()
                    os.fsync(file.fileno())
                os.replace(temporary, self.state_file, src_dir_fd=directory, dst_dir_fd=directory)
                os.fsync(directory)
            finally:
                os.close(directory)
        except OSError:
            raise StateError(f"cannot persist {self.state_file}; check the dispatcher state directory") from None
        self.data = data


class Claims:
    """Pool-wide arbitration. The durable state, not a PID or the age of a file, owns a claim."""

    def __init__(self, root, states, pool):
        self.directory = root / pool.key
        self.states, self.pool = states, pool

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
            data = store.data if slot == SLOT else Store(directory, self.pool.state_file, slot=slot).data
            handles = list(data["ambiguous"])
            if data["active"] is not None:
                handles.append(data["active"]["handle"])
            for handle in handles:
                digest = handle_digest(handle)
                if digest in claims:
                    raise StateError("conflicting durable claims; reconcile dispatcher state before polling")
                claims.add(digest)
            blocked.update(data["retired"])
            # The slot that saw a definite refusal or missed pickup owns that handle's budget.
            if slot != SLOT:
                blocked.update(data["refusals"])
                blocked.update(data.get("unpicked", {}))
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

    def pin_user(self, store, login, lookup):
        def reconcile(candidate=None):
            with self._locked():
                pins = store.data.get("trust_ids", {})
                ids = {pins.get(login)} | {
                    Store(directory, self.pool.state_file, slot=slot).data.get("trust_ids", {}).get(login)
                    for slot, directory in self.states.items() if slot != SLOT
                }
                ids.discard(None)
                if len(ids) > 1:
                    raise ApiError(f"slots pinned trust user {login} to different accounts; reconcile the account")
                account = next(iter(ids), candidate)
                if account is not None and login not in pins:
                    store.save(trust_ids=pins | {login: account})
                    log(f"pinned trust user {login} to account {account}", self.pool)
                return account

        # No forge requests under the pool claim lock. Re-read peer pins before
        # publishing, so concurrent startup cannot write conflicting first IDs.
        account = reconcile()
        return account if account is not None else reconcile(lookup())

    def reserve(self, store, jobs):
        with self._locked() as fd:
            claims, blocked = self._ledger(store)
            # Count durable claims under the same lock as O_EXCL. Stale marker files do not
            # consume capacity; unresolved registrations do, even before a peer restarts.
            if len(claims) >= self.pool.max_slots:
                return None
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
    """The systemd credential sources for trusted delivery."""

    def __init__(self, sources):
        self.sources = sources

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


class Queue:
    """One pool's API and durable registration lifecycle on this slot."""

    def __init__(self, api, slot, store, claims, monotonic=time.monotonic, wall=time.time, *, vm_deadline, untrusted_limit, trust=None, trusted_egress=False):
        self.api, self.slot, self.store = api, slot, store
        self.pool = api.pool
        self.monotonic, self.wall = monotonic, wall
        self.trust = trust
        # The slot host has a second SNAT source (_ci-slots.nix egress.trusted). Used only
        # after a successful deliver, so never with trusted jobs off.
        self.trusted_egress = trusted_egress
        self.egress = None  # {"name", "state": open|refused|pending, "error"} for the active run
        self.vm_deadline = vm_deadline
        self.untrusted_limit = untrusted_limit  # From first observed pickup; persisted across restarts.
        self.claims = claims
        self.claims.recover(store)
        pins = store.data.get("trust_ids", {})
        keep = {login: account for login, account in pins.items() if login in self.pool.trust_users}
        if keep != pins:
            store.save(trust_ids=keep)
        self.pins_after = 0
        self.pins_ready = False
        self.pins_error = None
        if trust is None and (self.pool.trust_repos or self.pool.trust_users):
            self._log("trust allowlist configured but trusted jobs are off; no run gets CI upload credentials")
        self.api_after = self.api_delay = 0
        self.inventory_after = self.busy_after = 0
        self.busy_misses = 0
        self.observed = None
        self.last_waiting_at = None
        self.stop_queued = None  # (slot run name, monotonic time) of the last dispatcher stop
        self.reset_pending = False  # reset-failed still owed for a stop that timed out
        self.identity_verified = False
        self.deadline_logged = False
        # The durable proof only permits revalidation; credentials are withdrawn at startup.
        self.verdict = None  # {"name", "state": pending|delivered|untrusted, "since": first resolution attempt}
        # Slot-local backoff for failed starts and missed pickups.
        self.pre_start_retries = {}

    def _log(self, message):
        log(message, self.pool)

    def api_failed(self, error):
        self.api_delay = min(60, max(POLL, 2 * self.api_delay))
        self.api_after = self.monotonic() + self.api_delay
        self._log(error)

    def api_ok(self):
        self.api_after = self.api_delay = 0

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
        if not snapshot.vm_idle:
            self._begin_revalidation()
        self.slot.withdraw(snapshot.run)

    def monitor(self):
        now = self.monotonic()
        active = self.store.data["active"]
        if "trusted" in active and self.verdict is not None and self.verdict["state"] == "untrusted":
            self._stop("previously trusted job failed revalidation")
            return POLL
        self._begin_revalidation()
        remaining = self._until_untrusted_limit()
        if remaining <= 0:
            self._stop("trust revalidation timed out" if self._revalidating() else "untrusted job reached its 65 min limit")
            return POLL
        if now >= self.busy_after:
            queued_at = self.store.data["active"]["queued_at"]
            interval = BUSY_POLL_FAST if self.wall() - queued_at < BUSY_FAST_WINDOW else BUSY_POLL
            if self._resolving():
                interval = POLL  # Deliver soon after pickup: builds before delivery aren't uploaded.
            self.busy_after = now + interval
            try:
                with self.api.within(remaining):
                    self._remote(False)
            except ApiError as error:
                self.busy_misses = 0
                self._log(error)
        if self.verdict is not None and self.verdict["state"] == "untrusted" and "trusted" in self.store.data["active"]:
            # Do not grant another recovery window if the dispatcher dies while stopping the VM.
            active = self.store.data["active"]
            now_wall = self.wall()
            if active["revalidate_by"] > now_wall:
                self.store.save(active=active | {"revalidate_by": now_wall})
            self._stop("previously trusted job failed revalidation")
            return POLL
        return max(0, min(POLL, self.busy_after - self.monotonic(), self._until_untrusted_limit()))

    def _begin_revalidation(self):
        active = self.store.data["active"]
        if self._revalidating() and "revalidate_by" not in active:
            self.store.save(active=active | {"revalidate_by": self.wall() + TRUST_DEADLINE})

    def _revalidating(self):
        active = self.store.data["active"]
        return self.trust is not None and active is not None and "trusted" in active and (
            self.verdict is None or self.verdict["state"] == "pending"
        )

    def _until_untrusted_limit(self):
        active = self.store.data["active"]
        if self.verdict is not None and self.verdict["name"] == active["name"] and self.verdict["state"] == "delivered":
            return float("inf")
        if self._revalidating():
            return active["revalidate_by"] - self.wall()
        # If the forge never reports pickup, the start time is the safe
        # fallback; a broken API must not grant the longer trusted budget.
        return active.get("picked_up_at", active["queued_at"]) + self.untrusted_limit - self.wall()

    def idle_jobs(self):
        if self.monotonic() >= self.api_after:
            try:
                return self._remote(True)
            except ApiError as error:
                self.api_failed(error)
        return None

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
                self.last_waiting_at = active["queued_at"]
                self._log(f"monitoring VM for runner {active['runner']['id']}; systemd owns its deadline")
            if self.wall() >= active["queued_at"] + self.vm_deadline and not self.deadline_logged:
                self.deadline_logged = True
                self._log("VM is still busy past its recorded deadline estimate; inspect the systemd unit")
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
            self._log("scrubbing idle slot with unknown run marker")
        self.slot.scrub(snapshot.run)
        self.verdict = None
        self.egress = None
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
                    self._log(f"slot ended {result}; left failed for inspection")
            if self.reset_pending:
                # Not fatal: retried on the next idle pass until Result is success again.
                try:
                    self.slot.reset_failed()
                except SlotError as error:
                    self._log(error)
                else:
                    self.reset_pending = False
                    self._log(f"reset {VM} after its cancellation stop timed out")
        if active is None or active["phase"] in ("cleanup", "release"):
            return True
        if active["phase"] == "intent":
            ambiguous = self.store.data["ambiguous"] | {active["handle"]: {"name": active["name"], "runners": None}}
            self.store.save(active=None, ambiguous=ambiguous)
            self._log(f"registration outcome unresolved for {active['name']}; searching owned runners by exact name")
        elif active["phase"] == "registered":
            self.store.save(active=active | {"phase": "release"})
            self._log(f"VM start not submitted; local files scrubbed for unused runner {active['runner']['id']}")
        else:
            cleanup = {key: value for key, value in active.items() if key not in ("picked_up_at", "trusted", "revalidate_by")}
            cleanup.update(phase="cleanup", queued_at=None)
            self.store.save(active=cleanup)
            self._log(f"VM idle ({result}); local files scrubbed for runner {active['runner']['id']}")
        return True

    def _remote(self, idle):
        data = self.store.data
        owner, account = self.api.identify(data["owner_id"])
        if not self.identity_verified:
            self._log(f"Forgejo PAT identity verified as {self.pool.login}")
            self.identity_verified = True
        if data["owner_id"] is None:
            if self.monotonic() < self.inventory_after:
                return []
            if any(row["owner_id"] == owner and matches(NAME, row["name"]) for row in self._inventory()):
                raise ApiError(f"{self.pool.state_file} absent but a dispatcher-named runner exists; reconcile before enabling dispatch")
            self.store.save(owner_id=owner)
        if idle and self.trust is not None and not self.pins_ready and self.monotonic() >= self.pins_after:
            self.pins_after = self.monotonic() + BUSY_POLL
            try:
                with self.api.within(REQUEST_TIMEOUT):
                    self._pin_trust_users(account, resolve=True)
            except ApiError as error:
                if str(error) != self.pins_error:
                    self._log(f"startup trust pins incomplete: {error}")
                self.pins_error = str(error)
        active = data["active"]
        if idle and active is not None:
            self.api.delete(active["runner"])
            if active["phase"] == "release":
                handle = active["handle"]
                self.claims.finish(self.store, (handle,), active=None)
                delay = self._back_off_start(handle)
                self._log(f"released job after unused runner {active['runner']['id']} was deleted; retry in {delay}s")
                active = None
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
                    self._log(error)
                else:
                    inventory_ok = True
                    self._delete_recovered()
        jobs = self.api.jobs(owner)
        if idle and active is not None:
            self._finish_started(active, jobs)
        seen = {job["handle"] for job in jobs}
        self._observe_queue(seen, inventory_ok)
        if not idle:
            self._check_cancelled(seen)
            active = self.store.data["active"]
            target = next((job for job in jobs if job["handle"] == active["handle"]), None)
            if target is not None and target["status"] == "waiting" and target["task_id"] == 0:
                self.last_waiting_at = self.wall()
            elif self._is_picked_up(target):
                if "picked_up_at" not in active:
                    now = self.wall()
                    timely = now - self.last_waiting_at <= BUSY_POLL + 3 * REQUEST_TIMEOUT
                    # A poll after an outage must not give an already-running job a fresh 65 minutes.
                    picked_up_at = now if timely else self.last_waiting_at
                    self.store.save(active=active | {"picked_up_at": picked_up_at})
                    self.pre_start_retries.pop(active["handle"], None)
                if self.trust is not None and self._until_untrusted_limit() > 0:
                    self._settle_trust(target, owner, account)
            return
        data = self.store.data
        blocked = set(data["retired"]) | data["ambiguous"].keys()
        now = self.monotonic()
        return [
            job for job in jobs
            if job["status"] == "waiting" and job["task_id"] == 0
            and len(job["runs_on"]) == 1 and job["runs_on"][0] in self.pool.labels
            and job["handle"] not in blocked and now >= self.pre_start_retries.get(job["handle"], (0, 0))[1]
        ]

    def _back_off_start(self, handle):
        previous, _ = self.pre_start_retries.get(handle, (0, 0))
        delay = min(PRE_START_MAX_BACKOFF, max(POLL, previous * 2))
        self.pre_start_retries[handle] = delay, self.monotonic() + delay
        return delay

    def _finish_started(self, active, jobs):
        handle = active["handle"]
        waiting = any(job["handle"] == handle and job["status"] == "waiting" and job["task_id"] == 0 for job in jobs)
        data = self.store.data
        unpicked = data.get("unpicked", {}).copy()
        count = unpicked.pop(handle, 0) + 1
        retired = data["retired"]
        if waiting:
            if count < REFUSAL_LIMIT:
                unpicked[handle] = count
                delay = self._back_off_start(handle)
                self._log(f"VM ended without pickup ({count}/{REFUSAL_LIMIT}); retry in {delay}s")
            else:
                self._log(f"VM ended without pickup ({count}/{REFUSAL_LIMIT}); retiring handle")
        if not waiting or count >= REFUSAL_LIMIT:
            retired = [*retired, handle]
        self.claims.finish(self.store, (handle,), active=None, retired=retired, unpicked=unpicked)

    def _check_cancelled(self, seen):
        if self.store.data["active"]["handle"] in seen:
            self.busy_misses = 0
        else:
            self.busy_misses += 1
            if self.busy_misses >= 2:
                self._stop("target absent from consecutive job polls")

    def _stop(self, reason):
        active = self.store.data["active"]
        # Don't log and queue the same stop while systemd is still deactivating.
        stopped = self.stop_queued
        if stopped is not None and stopped[0] == active["name"] and self.monotonic() - stopped[1] < STOP_RETRY:
            return
        if not self.slot.observe().vm_idle:
            self.slot.stop(active["name"])
            self.stop_queued = (active["name"], self.monotonic())
            self._log(f"queued VM stop: runner {active['runner']['id']} {reason}")

    def _resolving(self):
        if self.trust is None:
            return False
        if self._revalidating():
            return True
        verdict = self.verdict
        if verdict is None or verdict["name"] != self.store.data["active"]["name"]:
            return True
        return verdict["state"] == "pending" and (
            verdict["since"] is None or self.monotonic() - verdict["since"] < TRUST_DEADLINE
        )

    def _settle_trust(self, job, owner, account):
        """Deliver the CI upload credentials only to a slot whose exact run is trusted.

        Every boot is untrusted. Resolution waits for the slot's runner to take the job (status running,
        task_id set), then follows task_id -> task -> run_number -> run, cross-checks task and run, and
        rechecks job and run just before writing. Errors retry until TRUST_DEADLINE after pickup, then give up.
        """
        active = self.store.data["active"]
        if self.verdict is None or self.verdict["name"] != active["name"]:
            self.verdict = {"name": active["name"], "state": "pending", "since": None}
        verdict = self.verdict
        if verdict["state"] == "delivered":
            self._open_egress(active["name"])  # Retries a pending egress on later polls.
        if verdict["state"] != "pending":
            return
        repo_id = job["repo_id"]
        repo = self.pool.trust_repos.get(repo_id)
        if repo is None:
            verdict["state"] = "untrusted"
            self._log("untrusted: repository not in the trust allowlist; CI upload credentials withheld")
            return
        proof = active.get("trusted")
        if proof is not None and job["task_id"] != proof["task_id"]:
            verdict["state"] = "untrusted"
            self._log("untrusted: task changed since delivery; CI upload credentials withheld")
            return
        path = f"/repos/{repo['owner']}/{repo['name']}"
        if verdict["since"] is None:
            verdict["since"] = self.monotonic()
        remaining = verdict["since"] + TRUST_DEADLINE - self.monotonic()
        try:
            if remaining <= 0:
                raise ApiError("trust lookup deadline reached")
            with self.api.within(remaining):
                trust_ids = self._pin_trust_users(account)
                reason, run = self._resolve(job, path, owner, trust_ids)
                if proof is not None and run["id"] != proof["run_id"]:
                    reason = "run changed since delivery"
                if reason is None:
                    # Still the same attempt, running on the same task, and the same trusted run.
                    again = next((row for row in self.api.jobs(owner) if row["handle"] == active["handle"]), None)
                    if not self._is_picked_up(again) or any(again[key] != job[key] for key in ("id", "repo_id", "attempt", "task_id")):
                        raise ApiError("job changed before delivery")
                    rerun = self.api.run_by_number(path, run["index_in_repo"])
                    if rerun["id"] != run["id"]:
                        raise ApiError("run changed before delivery")
                    reason = trusted_run(rerun, repo_id, owner, self.pool, trust_ids)
                    if self.monotonic() - verdict["since"] >= TRUST_DEADLINE or self._until_untrusted_limit() <= 0:
                        raise ApiError("trust lookup deadline reached")
        except ApiError as error:
            self._defer(verdict, f"trust lookup pending: {error}", error)
            return
        if reason is not None:
            verdict["state"] = "untrusted"
            self._log(f"untrusted: run #{run['index_in_repo']} ({reason}); CI upload credentials withheld")
            return
        secrets = self.trust.secrets()
        if secrets is None:
            verdict["state"] = "untrusted"
            self._log("untrusted: trusted-ci-signing-key or trusted-ncps-netrc credential missing or malformed; withheld")
            return
        try:
            if self.slot.observe().vm_idle:
                return  # The next tick reconciles the stopped slot; never write into a directory being scrubbed.
            if self._until_untrusted_limit() <= 0:
                return
            self.slot.deliver(active["name"], secrets)
        except SlotError as error:
            self._defer(verdict, f"delivery pending: {error}", error)
            return
        active = active | {"trusted": {"task_id": job["task_id"], "run_id": run["id"]}}
        active.pop("revalidate_by", None)
        self.store.save(active=active)
        verdict["state"] = "delivered"
        self._log(f"trusted: run #{run['index_in_repo']} ({run['trigger_event']}); delivered CI upload credentials")
        self._open_egress(active["name"])

    def _open_egress(self, name):
        """Move a delivered run to the slot host's trusted source. Withdraw, scrub and the VM's stop end it.

        Only reached after a successful deliver, which needs trusted jobs on. A failure leaves the run on the
        untrusted source: it keeps its credentials but can reach only the forges and ncps.
        """
        if not self.trusted_egress or self.trust is None:
            return
        egress = self.egress if self.egress is not None and self.egress["name"] == name else None
        if egress is not None and egress["state"] in ("open", "refused"):
            return
        try:
            self.slot.egress_trusted(name)
        except EgressRefused as error:
            self.egress = {"name": name, "state": "refused", "error": str(error)}
            self._log(f"trusted egress refused for this run: {error}; it stays on the untrusted source")
            return
        except SlotError as error:
            if egress is None or egress["error"] != str(error):
                self._log(f"trusted egress pending: {error}")
            self.egress = {"name": name, "state": "pending", "error": str(error)}
            return
        self.egress = {"name": name, "state": "open", "error": None}
        self._log("trusted egress: the run now leaves from the slot host's trusted source")

    def _defer(self, verdict, message, error):
        if self.monotonic() - verdict["since"] >= TRUST_DEADLINE:
            verdict["state"] = "untrusted"
            self._log(f"untrusted: trust lookup gave up after {TRUST_DEADLINE // 60} min ({error}); CI upload credentials withheld")
        else:
            self._log(message)

    @staticmethod
    def _is_picked_up(job):
        return job is not None and job["status"] == "running" and job["task_id"] > 0

    def _pin_trust_users(self, account, *, resolve=False):
        if not self.pins_ready:
            error = None
            for login in sorted(self.pool.trust_users):
                try:
                    def lookup():
                        if not resolve:
                            raise ApiError(self.pins_error or "trust user has no idle-poll pin")
                        return account if login == self.pool.login else self.api.user(login)

                    pinned = self.claims.pin_user(self.store, login, lookup)
                    if login == self.pool.login and pinned != account:
                        raise ApiError("PAT account ID differs from the pinned trust user; reconcile the account")
                except ApiError as failure:
                    error = failure
            if error is not None:
                raise error
            self.pins_ready = True
        pins = self.store.data.get("trust_ids", {})
        if self.pool.login in pins and pins[self.pool.login] != account:
            raise ApiError("PAT account ID differs from the pinned trust user; reconcile the account")
        return pins

    def _resolve(self, job, path, owner, trust_ids):
        """(None, run) for a trusted run, else (reason, run). Lookup failures raise ApiError."""
        repository = self.api.repository(path, job["repo_id"], owner)
        task = self.api.task(path, job["task_id"])
        run = self.api.run_by_number(path, task["run_number"])
        if run.get("commit_sha") != task["head_sha"] or run.get("workflow_id") != task["workflow_id"]:
            return "task and run disagree", run
        reason = trusted_run(run, job["repo_id"], owner, self.pool, trust_ids)
        if reason is not None:
            return reason, run
        # A pull mirror's sync pushes as the repository owner (services/mirror/mirror_pull.go SyncPushCommits).
        if repository["mirror"]:
            return "repository is a pull mirror", run
        if not self.api.deploy_keys_read_only(path):
            return "repository has a write deploy key", run
        if self.pool.kind == "user" and trust_ids.get(self.pool.owner) != owner:
            return "repository owner is outside trust.users", run
        if gap := self.api.writer_gap(path, trust_ids):
            return gap, run
        branch = run["repository"]["default_branch"]
        return protection_gap(self.api.branch_protections(path), branch, self.pool.trust_users), run

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
        unpicked = data.get("unpicked", {})
        if unpicked.keys() - seen:
            changes["unpicked"] = {handle: count for handle, count in unpicked.items() if handle in seen}
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
                self._log(f"expired registration intent for {intent['name']}: no queued handle or exact runner match")
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
            self._log(f"{len(unmatched)} unresolved registration(s); no exact runner match for {', '.join(unmatched[:3])}")

    def _delete_recovered(self):
        for handle, intent in self.store.data["ambiguous"].items():
            if intent["runners"] is not None:
                for runner in intent["runners"]:
                    self.api.delete(runner)
                data = self.store.data
                remaining = data["ambiguous"].copy()
                del remaining[handle]
                self.claims.finish(self.store, (handle,), ambiguous=remaining, retired=[*data["retired"], handle])

    def submit(self, reserved):
        job, digest, active = reserved
        handle = active["handle"]
        self._log(f"registering runner for job {job['id']} attempt {job['attempt']} ({digest})")
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
        self.slot.stage(active["name"], runner["uuid"], token, handle, self.pool.url, job["runs_on"][0])
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
        self._log(f"queued VM start for runner {runner['id']}")

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
            self._log("retiring handle after repeated registration refusals spanning at least one hour")


class Dispatcher:
    """Run one slot, rotating through queues and taking the oldest eligible job within each queue."""

    def __init__(self, queues, monotonic=time.monotonic, *, pause=PAUSE_FILE, host_pause=HOST_PAUSE_FILE):
        self.queues = tuple(queues)
        self.monotonic, self.pause, self.host_pause = monotonic, pause, host_pause
        active = [index for index, queue in enumerate(self.queues) if queue.store.data["active"] is not None]
        if len(active) > 1:
            raise StateError("multiple pools own the slot; reconcile dispatcher state before polling")
        self.local_queue = self.queues[active[0] if active else 0]
        self.next_pool = (active[0] + 1) % len(self.queues) if active else 0
        self.start_refusals = self.start_delay = self.start_after = 0
        self.space_error = None

    def withdraw(self):
        self.local_queue.withdraw()

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

    def _space_ready(self, slot):
        try:
            slot.check_space()
        except SlotError as error:
            message = str(error)
            if message != self.space_error:
                log(f"pre-claim check-space failed: {message}")
                self.space_error = message
            return False
        if self.space_error is not None:
            log("pre-claim check-space recovered")
            self.space_error = None
        return True

    def _idle(self):
        local = self.local_queue
        # Finish any known runner cleanup before selecting new work. Reuse the
        # same queue snapshot if its turn comes up later in this tick.
        cleaning = local.store.data["active"] is not None
        jobs_after_cleanup = local.idle_jobs() if cleaning else None
        if local.store.data["active"] is not None:
            return
        can_start = self.monotonic() >= self.start_after
        space_ready = None
        for offset in range(len(self.queues)):
            index = (self.next_pool + offset) % len(self.queues)
            queue = self.queues[index]
            jobs = jobs_after_cleanup if cleaning and queue is local else queue.idle_jobs()
            if jobs is None:
                continue  # API cooldown or failure in this pool, not its peers.
            if can_start and jobs and not self._paused():
                if space_ready is None:
                    space_ready = self._space_ready(queue.slot)
                if space_ready:
                    reserved = queue.claims.reserve(queue.store, sorted(jobs, key=lambda job: job["id"]))
                    if reserved is not None:
                        self.next_pool = (index + 1) % len(self.queues)
                        self.local_queue = queue
                        try:
                            queue.submit(reserved)
                        except StartRefused as error:
                            self.start_refusals += 1
                            self.start_delay = min(START_MAX_BACKOFF, max(POLL, self.start_delay * 2))
                            self.start_after = self.monotonic() + self.start_delay
                            log(f"start refused; slot dispatch backs off for {self.start_delay}s: {error}", queue.pool)
                            if self.start_refusals == START_ESCALATE:
                                log(f"{START_ESCALATE} consecutive start refusals; inspect slotctl and the slot host")
                        except ApiError as error:
                            queue.api_failed(error)
                        else:
                            self.start_refusals = self.start_delay = self.start_after = 0
                            queue.api_ok()
                        return
            queue.api_ok()

    def tick(self):
        try:
            if not self.local_queue._local():
                # This is also proof of submission when systemd's reply was lost.
                self.start_refusals = self.start_delay = self.start_after = 0
                return self.local_queue.monitor()
            self._idle()
        except SlotError as error:
            log(error, self.local_queue.pool)
        return POLL


def load_pools(path):
    try:
        with path.open("rb") as file:
            entries = json.load(file)
        if not isinstance(entries, dict) or not entries:
            raise ValueError
        pools = [Pool(name, **entry) for name, entry in entries.items()]
        if len({pool.key for pool in pools}) != len(pools):
            raise ValueError
        if len({(pool.forge, pool.login) for pool in pools}) != len({pool.forge for pool in pools}):
            raise ValueError
        return pools
    except (OSError, TypeError, ValueError, RecursionError):
        raise StateError("invalid dispatcher pool configuration; refusing dispatch") from None


def check_removed_pools(directory, pools):
    files = {pool.state_file for pool in pools}
    for path in sorted(directory.glob("pool-*.json")) + [directory / "state.json"]:
        if path.name not in files:
            data = Store(directory, path.name).data
            if data["active"] is not None or data["ambiguous"]:
                raise StateError("a removed pool still owns registrations; restore its configuration and drain it")


def parse_arguments(argv=None):
    """The command line for one slot serving the configured pools."""
    parser = argparse.ArgumentParser(description=__doc__)
    # Every slot setting is required: a dispatcher must never fall back to another slot's identity.
    parser.add_argument("--slot", required=True, help="the slot's microVM name, e.g. ryza-eph-1")
    parser.add_argument("--machine", required=True, help="the slot host's name")
    parser.add_argument("--vm-deadline", type=int, required=True, help="estimated host VM deadline in seconds")
    parser.add_argument("--untrusted-limit", type=int, required=True, help="untrusted job limit in seconds")
    transport = parser.add_mutually_exclusive_group(required=True)
    transport.add_argument("--slotctl", type=Path, help="the local slot agent")
    transport.add_argument("--ssh-command", type=Path, help="the pinned SSH wrapper for the remote slot agent")
    parser.add_argument("--pools", type=Path, required=True, help="JSON configuration of the pools this slot serves")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--claim-states", type=Path, required=True, help="JSON map of slot names to state directories")
    parser.add_argument("--pause-file", type=Path, default=PAUSE_FILE)
    parser.add_argument("--host-pause-file", type=Path, default=HOST_PAUSE_FILE)
    parser.add_argument("--trusted-jobs", action="store_true", help="deliver CI upload credentials to trusted runs")
    parser.add_argument("--trusted-egress", action="store_true", help="move delivered runs to the slot host's trusted source")
    args = parser.parse_args(argv)
    if not positive(args.vm_deadline):
        parser.error("--vm-deadline must be positive")
    if not positive(args.untrusted_limit):
        parser.error("--untrusted-limit must be positive")
    for path in (args.slotctl or args.ssh_command, args.pools, args.state_dir, args.claim_states, args.pause_file, args.host_pause_file):
        if not path.is_absolute():
            parser.error("dispatcher paths must be absolute")
    # Last, so a refused command line never leaves the process half configured.
    try:
        configure(args.slot, args.machine)
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
    credential_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    credentials = Path(credential_dir) if credential_dir else None
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
            pools = load_pools(args.pools)
            check_removed_pools(args.state_dir, pools)
            states = claim_states(args.claim_states, args.state_dir)
            trust = Trust(credentials) if args.trusted_jobs else None
            queues = [
                Queue(
                    Forgejo(pool, credentials / f"forgejo-pat-{pool.forge}" if credentials is not None else None),
                    slot, Store(args.state_dir, pool.state_file), Claims(CLAIM_ROOT, states, pool),
                    vm_deadline=args.vm_deadline, untrusted_limit=args.untrusted_limit, trust=trust,
                    trusted_egress=args.trusted_egress,
                )
                for pool in pools
            ]
            dispatcher = Dispatcher(queues, pause=args.pause_file, host_pause=args.host_pause_file)
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
