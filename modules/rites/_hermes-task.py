"""Stygies task state, in one of two modes.

Slot mode (HERMES_TASK_MODE unset; the company wrappers): one active task and a FIFO queue
per state dir. The launcher holds .task-lock for this entire process.

Worktree mode (HERMES_TASK_MODE=worktrees; the personal coder): no slot, no queue. Every live
task has its own record and, once it records a branch, its own git worktree beside the base
clone. This process takes .task-lock itself (README, "Hermes task worktrees").
"""

import argparse
import fcntl
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import NamedTuple


ROOM_ID = re.compile(r"!(?:[^\s:]+:\S+|[A-Za-z0-9_-]+)")
THREAD_ID = re.compile(r"\$[A-Za-z0-9_+/=-]+")
APP_PREFIX = "app:"
APP_ID = re.compile(r"[0-9a-f]{16}")
PROJECT = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


class Task(NamedTuple):
    started_at: str
    room: str
    thread: str
    project: str
    branch: str
    summary: str

    @property
    def origin(self):
        return (self.room, self.thread)

    @property
    def kind(self):
        return "app" if self.room.startswith(APP_PREFIX) else "matrix"

    def queued_metadata(self):
        return {"origin_kind": self.kind, "project": self.project, "queued_at": self.started_at}

    def as_json(self, owned):
        if self.kind == "matrix":
            return self._asdict()
        if not owned:
            return {"origin_kind": "app", "project": self.project}
        data = self._asdict()
        del data["room"], data["thread"]
        data["origin_kind"] = "app"
        data["session_id"] = self.room.removeprefix(APP_PREFIX)
        return data


def clean(text):
    text = re.sub(r"[\t\r\n]+", " ", text).strip()
    if not text:
        raise argparse.ArgumentTypeError("task fields must not be empty")
    return text


def project_name(text):
    if not PROJECT.fullmatch(text):
        raise argparse.ArgumentTypeError("expected a repository basename")
    return text


def app_projects(parser):
    try:
        projects = json.loads(os.environ.get("HERMES_TASK_APP_PROJECTS", "[]"))
    except ValueError:
        projects = None
    if not isinstance(projects, list) or not all(isinstance(name, str) for name in projects):
        parser.exit(2, "HERMES_TASK_APP_PROJECTS must be a JSON list of strings.\n")
    return projects


def env_list(parser, name):
    """An optional JSON list of strings; None when the variable is unset."""
    raw = os.environ.get(name)
    if raw is None:
        return None
    try:
        values = json.loads(raw)
    except ValueError:
        values = None
    if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
        parser.exit(2, f"{name} must be a JSON list of strings.\n")
    return values


def state_dir(parser):
    """The personal coder keeps ~/personal; the company wrappers set their own slot."""
    raw = os.environ.get("HERMES_TASK_STATE_DIR")
    if raw is None:
        return Path.home() / "personal"
    path = Path(raw)
    if not path.is_absolute():
        parser.exit(2, "HERMES_TASK_STATE_DIR must be an absolute path.\n")
    return path


def branch_pattern(parser):
    raw = os.environ.get("HERMES_TASK_BRANCH_PATTERN")
    if raw is None:
        return None
    try:
        return re.compile(raw)
    except re.error:
        parser.exit(2, "HERMES_TASK_BRANCH_PATTERN must be a valid regular expression.\n")


def read_tasks(path):
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return []
    if not text:
        return []
    tasks = []
    for line_number, line in enumerate(text.removesuffix("\n").split("\n"), 1):
        fields = line.split("\t")
        if len(fields) != 6:
            raise ValueError(f"line {line_number}: expected six fields")
        task = Task(*fields)
        try:
            if datetime.fromisoformat(task.started_at).tzinfo is None:
                raise ValueError("missing timezone")
        except ValueError:
            raise ValueError(f"line {line_number}: invalid started_at") from None
        if task.room.startswith(APP_PREFIX):
            if task.thread or not APP_ID.fullmatch(task.room.removeprefix(APP_PREFIX)):
                raise ValueError(f"line {line_number}: invalid app origin")
        elif not ROOM_ID.fullmatch(task.room) or not THREAD_ID.fullmatch(task.thread):
            raise ValueError(f"line {line_number}: invalid Matrix room or thread ID")
        tasks.append(task)
    return tasks


def load_state(path, parser, repair_at):
    try:
        return read_tasks(path)
    except ValueError as error:
        if repair_at is None:
            parser.exit(2, f"Invalid task state in {path.name} ({error}); ask manjo for 'clear task'.\n")
        backup = path.with_name(f"{path.name}.bad-{repair_at}")
        path.rename(backup)
        print(f"Moved invalid task state to {backup.name}", file=sys.stderr)
        return []


def write_tasks(path, tasks):
    if not tasks:
        path.unlink(missing_ok=True)
        return
    with NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        tmp = Path(stream.name)
        try:
            stream.writelines("\t".join(task) + "\n" for task in tasks)
            stream.close()
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)


def queue_position(queue, origin):
    return next((i for i, task in enumerate(queue, 1) if task.origin == origin), None)


def task_stamp(now, active, queue):
    # The launcher holds the lock. Keep new timestamps distinct from all live
    # ones, even when two calls see the same clock reading or the clock moves back.
    latest = max(
        (datetime.fromisoformat(task.started_at) for task in queue),
        default=now - timedelta(microseconds=1),
    )
    if active is not None:
        latest = max(latest, datetime.fromisoformat(active.started_at))
    if now <= latest:
        now = latest.astimezone(UTC) + timedelta(microseconds=1)
    return now.isoformat().replace("+00:00", "Z")


def slot_main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="action", required=True)
    status = commands.add_parser("task-status")
    status.add_argument("--queue", action="store_true", help="list queued positions, timestamps and summaries")
    commands.add_parser("task-clear")
    drop = commands.add_parser("task-drop")
    drop.add_argument("position", type=int)
    drop.add_argument("queued_at", help="exact timestamp from task-status --queue")
    claim = commands.add_parser("task-claim")
    done = commands.add_parser("task-done")
    branch = commands.add_parser("task-branch")
    for command in (status, claim, done, branch):
        command.add_argument("--app", metavar="ID", help="app task ID ('new' to claim)")
        command.add_argument("room", nargs="?")
        command.add_argument("thread", nargs="?")
    claim.add_argument("project", type=project_name)
    claim.add_argument("summary", choices=("-",), help="read the summary from stdin")
    for command in (done, branch):
        command.add_argument("started_at")
    branch.add_argument("branch", type=clean)
    argv = sys.argv[1:]
    if argv in (["task-status", "--"], ["task-clear", "--"]):
        argv.pop()
    args = parser.parse_args(argv)
    action = args.action
    origin = None
    mint_app = False
    if action not in ("task-clear", "task-drop"):
        if args.app is not None:
            if args.room is not None or args.thread is not None:
                parser.exit(2, "Use either --app or Matrix room and thread IDs.\n")
            if action == "task-claim":
                if args.app != "new":
                    parser.exit(2, "Use --app new to claim a new app task.\n")
                mint_app = True
            elif not APP_ID.fullmatch(args.app):
                parser.exit(2, "Invalid app task ID.\n")
            else:
                origin = (APP_PREFIX + args.app, "")
        elif action != "task-status" or args.room is not None:
            if not ROOM_ID.fullmatch(args.room or ""):
                parser.exit(2, "Invalid Matrix room ID.\n")
            if not THREAD_ID.fullmatch(args.thread or ""):
                parser.exit(2, "Invalid Matrix thread/event ID.\n")
            origin = (args.room, args.thread)
    # All unset in the personal coder's launcher; the company wrappers set them.
    work = state_dir(parser)
    allowed_projects = env_list(parser, "HERMES_TASK_PROJECTS")
    allowed_rooms = env_list(parser, "HERMES_TASK_ROOMS")
    # Set only when a personal project has no Matrix room; the app is its only origin.
    app_only = env_list(parser, "HERMES_TASK_APP_ONLY_PROJECTS")
    pattern = branch_pattern(parser)
    if allowed_rooms is not None and origin is not None and not origin[0].startswith(APP_PREFIX):
        if origin[0] not in allowed_rooms:
            parser.exit(2, "This Matrix room does not use these task commands.\n")
    if pattern is not None and action == "task-branch" and not pattern.fullmatch(args.branch):
        parser.exit(2, "Branch name does not match the required pattern.\n")
    list_queue = action == "task-status" and args.queue
    if list_queue and origin is not None:
        parser.exit(2, "Use --queue without an origin.\n")
    if action == "task-claim":
        if mint_app and args.project not in app_projects(parser):
            parser.exit(2, "Project is not enabled for app tasks.\n")
        if not mint_app and app_only is not None and args.project in app_only:
            parser.exit(2, "Project is app-only; claim it from the Hermes app.\n")
        if allowed_projects is not None and args.project not in allowed_projects:
            parser.exit(2, "Project is not enabled for these task commands.\n")
        try:
            summary = clean(sys.stdin.read())
        except argparse.ArgumentTypeError as error:
            parser.exit(2, f"Invalid task summary: {error}.\n")

    current_path = work / ".current-task"
    queue_path = work / ".task-queue"
    now = datetime.now(UTC)
    repair_at = now.strftime("%Y%m%dT%H%M%S%fZ") if action == "task-clear" else None
    current = load_state(current_path, parser, repair_at)
    active = current[0] if current else None
    queue = load_state(queue_path, parser, repair_at)
    # Promotion writes the slot first. If interrupted before trimming the queue,
    # the promoted task is already active, not another task to start.
    if active and queue and active.origin == queue[0].origin:
        queue.pop(0)
    position = None
    session_id = None
    if mint_app:
        while True:
            session_id = secrets.token_hex(8)
            origin = (APP_PREFIX + session_id, "")
            if (not active or active.origin != origin) and queue_position(queue, origin) is None:
                break

    if action == "task-status":
        result = "active" if active else "idle"
        if origin is not None:
            position = queue_position(queue, origin)
    elif action == "task-claim":
        if active is None:
            if queue:
                parser.exit(2, "Queue exists without an active task; ask manjo for 'clear task'.\n")
            active = Task(task_stamp(now, active, queue), *origin, args.project, "pending", summary)
            write_tasks(current_path, [active])
            result = "claimed"
        elif active.origin == origin:
            result = "active"
        else:
            position = None if mint_app else queue_position(queue, origin)
            if position is None:
                queue.append(Task(task_stamp(now, active, queue), *origin, args.project, "pending", summary))
                write_tasks(queue_path, queue)
                position = len(queue)
            result = "queued"
    elif action == "task-drop":
        if not 1 <= args.position <= len(queue) or queue[args.position - 1].started_at != args.queued_at:
            parser.exit(2, "No queued task matches that position and queued_at timestamp.\n")
        dropped = queue.pop(args.position - 1)
        write_tasks(queue_path, queue)
        result = "dropped"
    else:
        if action != "task-clear" and (
            active is None or origin != active.origin or args.started_at != active.started_at
        ):
            parser.exit(2, "Task no longer owns the slot.\n")
        if action == "task-branch":
            active = active._replace(branch=args.branch)
            write_tasks(current_path, [active])
            result = "updated"
        elif queue:
            stamp = task_stamp(now, active, queue)
            active = queue.pop(0)._replace(started_at=stamp)
            write_tasks(current_path, [active])
            write_tasks(queue_path, queue)
            result = "handoff"
        else:
            write_tasks(queue_path, [])
            write_tasks(current_path, [])
            active = None
            result = "idle"

    age = max(now - datetime.fromisoformat(active.started_at), timedelta()) if active else None
    owned = active is not None and active.origin == origin
    response = {
        "result": result,
        "active": active.as_json(owned) if active else None,
        "age_seconds": int(age.total_seconds()) if age is not None else None,
        "possibly_stale": age is not None and age > timedelta(hours=12),
        "queue_position": position,
    }
    # The original Matrix commands and unscoped status keep master's JSON contract.
    if origin is not None and (action == "task-status" or origin[0].startswith(APP_PREFIX)):
        response["owned"] = owned
    if list_queue:
        if active and active.kind == "matrix":
            response["active"] = {
                "origin_kind": "matrix", "project": active.project, "summary": active.summary,
            }
        response["queue"] = [
            {"queue_position": i, **task.queued_metadata(), "summary": task.summary}
            for i, task in enumerate(queue, 1)
        ]
    if action == "task-drop":
        response["dropped"] = dropped.queued_metadata()
    if session_id is not None:
        response["session_id"] = session_id
        if position is not None:
            response["queued_at"] = queue[position - 1].started_at
    print(json.dumps(response))


# --- worktree mode ----------------------------------------------------------
#
# State: <state>/.task-state.json, one record per live task, replaced atomically (readers
# need no lock). Worktrees: <root>/.worktrees/<project>/<task_id>, beside the base clones
# <root>/<project>, never inside them. Git is slow on big trees, so `task-branch` reserves
# the branch and path under the lock, checks out without it, and relocks to finish; removed
# worktrees are renamed into <root>/.worktrees/.trash and deleted after the lock is released.

STATE_FILE = ".task-state.json"
LOCK_FILE = ".task-lock"
LEGACY_FILES = (".current-task", ".task-queue")
WORKTREES = ".worktrees"
TRASH = ".trash"
KEPT = ".kept"
PR_REMOTE = "origin"
PENDING = "pending"
LOCK_BUSY = 75
PREPARING_GRACE = timedelta(minutes=10)
TASK_ID = re.compile(r"[0-9a-f]{16}")
REMOTE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
ORPHAN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
POSITIVE = re.compile(r"[1-9][0-9]*")
FIELDS = ("task_id", "started_at", "last_active", "room", "thread", "project", "branch", "summary",
          "worktree", "legacy", "preparing", "reservation")
RESERVATION = {"reserved_at", "nonce", "action", "start"}
ACTIONS = ("adopt", "new", "track", "existing")
SHA = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")
# A killed checkout leaves Git's "initializing" lock; after this long it is a crash, not a slow checkout.
STALE_INIT = timedelta(hours=1)
# The relock after a long checkout waits longer than a normal command, so it doesn't strand a finished worktree.
RELOCK_WAIT = 60
IN_PROGRESS = ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG")
# Variables that would point git at another repository, index or namespace than -C names.
GIT_SCRUB = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
             "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX")


class Refusal(Exception):
    """A refused command: the message goes to stderr, the exit status is 2."""


class Config(NamedTuple):
    state: Path
    root: Path
    base_remote: str
    max_live: int | None
    stale: timedelta
    git: str
    lock_wait: float


def worktree_config(parser):
    state = state_dir(parser)
    raw_root = os.environ.get("HERMES_TASK_REPO_ROOT")
    root = state if raw_root is None else Path(raw_root)
    if not root.is_absolute():
        parser.exit(2, "HERMES_TASK_REPO_ROOT must be an absolute path.\n")
    base_remote = os.environ.get("HERMES_TASK_BASE_REMOTE", "upstream")
    if not REMOTE.fullmatch(base_remote):
        parser.exit(2, "HERMES_TASK_BASE_REMOTE must be a remote name.\n")
    raw_max = os.environ.get("HERMES_TASK_MAX_LIVE")
    if raw_max is not None and not POSITIVE.fullmatch(raw_max):
        parser.exit(2, "HERMES_TASK_MAX_LIVE must be a positive integer.\n")
    raw_stale = os.environ.get("HERMES_TASK_STALE_HOURS", "12")
    if not POSITIVE.fullmatch(raw_stale):
        parser.exit(2, "HERMES_TASK_STALE_HOURS must be a positive integer.\n")
    raw_wait = os.environ.get("HERMES_TASK_LOCK_WAIT", "10")
    try:
        lock_wait = float(raw_wait)
    except ValueError:
        lock_wait = -1
    if not 0 <= lock_wait <= 60:
        parser.exit(2, "HERMES_TASK_LOCK_WAIT must be 0 to 60 seconds.\n")
    return Config(
        state=Path(os.path.normpath(state)), root=Path(os.path.normpath(root)), base_remote=base_remote,
        max_live=None if raw_max is None else int(raw_max), stale=timedelta(hours=int(raw_stale)),
        git=os.environ.get("HERMES_TASK_GIT", "git"), lock_wait=lock_wait,
    )


def stamp(moment):
    return moment.isoformat().replace("+00:00", "Z")


def parse_time(text):
    moment = datetime.fromisoformat(text)
    if moment.tzinfo is None:
        raise ValueError("missing timezone")
    return moment


def real(path):
    return os.path.realpath(path)


def base_path(cfg, project):
    return cfg.root / project


def worktree_path(cfg, project, task_id):
    return cfg.root / WORKTREES / project / task_id


def origin_of(task):
    return (task["room"], task["thread"])


def origin_kind(task):
    return "app" if task["room"].startswith(APP_PREFIX) else "matrix"


def one_line(value):
    return isinstance(value, str) and value != "" and not re.search(r"[\t\r\n]", value)


# --- state ------------------------------------------------------------------


def check_record(cfg, record):
    if not isinstance(record, dict) or set(record) != set(FIELDS):
        raise ValueError("unexpected fields")
    if not all(isinstance(record[key], str) for key in FIELDS[:8]):
        raise ValueError("unexpected field types")
    if not TASK_ID.fullmatch(record["task_id"]):
        raise ValueError("invalid task_id")
    for key in ("started_at", "last_active"):
        try:
            parse_time(record[key])
        except ValueError:
            raise ValueError(f"invalid {key}") from None
    room, thread = origin_of(record)
    if room.startswith(APP_PREFIX):
        if thread or not APP_ID.fullmatch(room.removeprefix(APP_PREFIX)):
            raise ValueError("invalid app origin")
    elif not ROOM_ID.fullmatch(room) or not THREAD_ID.fullmatch(thread):
        raise ValueError("invalid Matrix room or thread ID")
    if not PROJECT.fullmatch(record["project"]):
        raise ValueError("invalid project")
    if not one_line(record["branch"]) or not one_line(record["summary"]):
        raise ValueError("invalid branch or summary")
    if not isinstance(record["legacy"], bool) or not isinstance(record["preparing"], bool):
        raise ValueError("invalid flags")
    reservation = record["reservation"]
    if record["preparing"] != (reservation is not None):
        raise ValueError("preparing without a reservation")
    if reservation is not None:
        if not isinstance(reservation, dict) or set(reservation) != RESERVATION:
            raise ValueError("invalid reservation")
        if (not isinstance(reservation["reserved_at"], str) or not isinstance(reservation["nonce"], str)
                or not TASK_ID.fullmatch(reservation["nonce"]) or reservation["action"] not in ACTIONS
                or not (reservation["start"] is None
                        or (isinstance(reservation["start"], str) and SHA.fullmatch(reservation["start"])))):
            raise ValueError("invalid reservation")
        try:
            parse_time(reservation["reserved_at"])
        except ValueError:
            raise ValueError("invalid reservation") from None
    worktree, pending = record["worktree"], record["branch"] == PENDING
    if record["legacy"]:
        if worktree != str(base_path(cfg, record["project"])) or pending or record["preparing"]:
            raise ValueError("invalid legacy task")
    elif worktree is None:
        if not pending or record["preparing"]:
            raise ValueError("a branch without a worktree")
    elif worktree != str(worktree_path(cfg, record["project"], record["task_id"])) or pending:
        raise ValueError("unexpected worktree path")


def load_live(cfg):
    """The live tasks; raises ValueError for anything this module would not have written."""
    try:
        text = (cfg.state / STATE_FILE).read_text(encoding="utf-8")
    except FileNotFoundError:
        return []
    data = json.loads(text)
    if (not isinstance(data, dict) or set(data) != {"version", "tasks"} or type(data["version"]) is not int or data["version"] != 1
            or not isinstance(data["tasks"], list)):
        raise ValueError("unexpected layout")
    return validate(cfg, data["tasks"])


def validate(cfg, tasks):
    for number, record in enumerate(tasks, 1):
        try:
            check_record(cfg, record)
        except ValueError as error:
            raise ValueError(f"task {number}: {error}") from None
    for what, key in (("task_id", lambda t: t["task_id"]), ("origin", origin_of)):
        values = [key(task) for task in tasks]
        if len(set(values)) != len(values):
            raise ValueError(f"duplicate {what}")
    branches = [(t["project"], t["branch"]) for t in tasks if t["branch"] != PENDING]
    if len(set(branches)) != len(branches):
        raise ValueError("two tasks record one branch")
    return tasks


def save_state(cfg, tasks):
    path = cfg.state / STATE_FILE
    if not tasks:
        path.unlink(missing_ok=True)
        return
    with NamedTemporaryFile(mode="w", encoding="utf-8", dir=cfg.state, delete=False) as stream:
        tmp = Path(stream.name)
        try:
            stream.write(json.dumps({"version": 1, "tasks": tasks}, indent=1) + "\n")
            stream.close()
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)


def mint_task_id(cfg, tasks, project):
    while True:
        task_id = secrets.token_hex(8)
        if all(t["task_id"] != task_id for t in tasks) and not os.path.lexists(worktree_path(cfg, project, task_id)):
            return task_id


def adopt_legacy(cfg, tasks, now, repair, moved):
    """Turn the old slot (.current-task) and queue (.task-queue) into live tasks, once.

    The active row keeps its recorded branch and goes on in its base clone (`legacy`);
    queued rows become pending tasks, keeping their queued_at as started_at. The new state
    is written before the old files are renamed, and rows already present (same origin)
    are skipped, so an interrupted run just finishes on the next command.
    """
    paths = [cfg.state / name for name in LEGACY_FILES]
    if not any(os.path.lexists(path) for path in paths):
        return tasks
    try:
        active = read_tasks(paths[0])
        if len(active) > 1:
            raise ValueError("more than one active task")
        rows = [(row, True) for row in active] + [(row, False) for row in read_tasks(paths[1])]
        adopted = []
        for row, was_active in rows:
            legacy = was_active and row.branch != PENDING
            if any(origin_of(t) == row.origin for t in tasks + adopted):
                continue
            record = {
                "task_id": mint_task_id(cfg, tasks + adopted, row.project), "started_at": row.started_at,
                "last_active": stamp(now), "room": row.room, "thread": row.thread, "project": row.project,
                "branch": row.branch if legacy else PENDING, "summary": row.summary,
                "worktree": str(base_path(cfg, row.project)) if legacy else None,
                "legacy": legacy, "preparing": False, "reservation": None,
            }
            check_record(cfg, record)
            adopted.append(record)
        merged = validate(cfg, tasks + adopted)  # e.g. no branch recorded twice
    except ValueError as error:
        if not repair:
            raise Refusal(f"Invalid old task slot state ({error}); ask manjo for 'clear task' (task-clear --repair).") from None
        suffix = "bad"
    else:
        save_state(cfg, merged)
        tasks, suffix = merged, "migrated"
    label = now.strftime("%Y%m%dT%H%M%S%fZ")
    for path in paths:
        if os.path.lexists(path):
            target = path.with_name(f"{path.name}.{suffix}-{label}")
            path.rename(target)
            moved.append(target.name)
    if suffix == "migrated":
        print(f"Moved the old task slot into {STATE_FILE}: {', '.join(moved)}", file=sys.stderr)
    return tasks


# --- lock -------------------------------------------------------------------


class Store:
    """The state dir's lock and its tasks, as of the last (re)lock."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.stream = None
        self.tasks = []

    def lock(self, wait=None):
        stream = open(self.cfg.state / LOCK_FILE, "ab")
        deadline = time.monotonic() + (self.cfg.lock_wait if wait is None else wait)
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    stream.close()
                    sys.exit(LOCK_BUSY)
                time.sleep(0.05)
        self.stream = stream

    def unlock(self):
        if self.stream is not None:
            fcntl.flock(self.stream, fcntl.LOCK_UN)
            self.stream.close()
            self.stream = None

    def reload(self):
        try:
            self.tasks = load_live(self.cfg)
        except ValueError as error:
            raise Refusal(f"Invalid task state in {STATE_FILE} ({error}); ask manjo for 'clear task' (task-clear --repair).") from None
        return self.tasks

    def save(self):
        save_state(self.cfg, self.tasks)


# --- git --------------------------------------------------------------------


def git_env(extra=None):
    env = {key: value for key, value in os.environ.items() if key not in GIT_SCRUB}
    env.update(extra or {})
    return env


def run_git(cfg, repo, *args, env=None):
    return subprocess.run([cfg.git, "-C", str(repo), *args], capture_output=True, text=True,
                          env=env or git_env(), check=False)


def git_out(cfg, repo, *args, what):
    result = run_git(cfg, repo, *args)
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()[-1:] or ["no output"]
        raise Refusal(f"{what} failed in {repo}: {detail[0]}")
    return result.stdout.strip()


def ref_exists(cfg, repo, ref):
    return run_git(cfg, repo, "show-ref", "--verify", "--quiet", ref).returncode == 0


def worktree_entries(cfg, base):
    """`git worktree list --porcelain -z` as dicts: path, and HEAD/branch/detached/locked/prunable."""
    out = git_out(cfg, base, "worktree", "list", "--porcelain", "-z", what="git worktree list")
    entries, current = [], None
    for field in out.split("\0"):
        if not field:
            if current is not None:
                entries.append(current)
            current = None
            continue
        key, _, value = field.partition(" ")
        if key == "worktree":
            if current is not None:
                entries.append(current)
            current = {"path": value}
        elif current is not None:
            current[key] = value
    if current is not None:
        entries.append(current)
    return entries


def entry_for(entries, path):
    return next((entry for entry in entries if real(entry["path"]) == real(path)), None)


def check_base(cfg, base):
    if not base.is_dir():
        raise Refusal(f"No base clone at {base}; set it up first (workspace step).")
    out = git_out(cfg, base, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-dir",
                  "--git-common-dir", what="git rev-parse").splitlines()
    if len(out) != 3 or real(out[0]) != real(base) or real(out[1]) != real(out[2]):
        raise Refusal(f"{base} is not a base clone (the top level of a repository with its own .git).")


def uncommitted(cfg, path):
    """Count of changed tracked files and untracked files that aren't ignored."""
    out = git_out(cfg, path, "status", "--porcelain", "--untracked-files=all", what="git status")
    return len(out.splitlines())


def snapshot(cfg, path, name, label):
    """Commit everything uncommitted in a worktree (ignored files aside) to refs/hermes/wip/<name>.

    A private index, so the worktree's own index and HEAD stay as they were; the commit's parent
    is HEAD, so commits only HEAD holds (a detached HEAD, a rebase) are kept too. Never replaces
    an existing ref. Returns the ref."""
    ref = f"refs/hermes/wip/{name}"
    index = cfg.state / f".wip-index-{secrets.token_hex(4)}"
    env = git_env({
        "GIT_INDEX_FILE": str(index), "GIT_AUTHOR_NAME": "Hermes task tools", "GIT_AUTHOR_EMAIL": "hermes@localhost",
        "GIT_COMMITTER_NAME": "Hermes task tools", "GIT_COMMITTER_EMAIL": "hermes@localhost",
    })
    try:
        def step(*args):
            result = run_git(cfg, path, *args, env=env)
            if result.returncode != 0:
                raise Refusal(f"Could not save the uncommitted work in {path} ({' '.join(args[:2])}).")
            return result.stdout.strip()
        step("read-tree", "HEAD")
        step("add", "-A")
        tree = step("write-tree")
        commit = step("commit-tree", tree, "-p", "HEAD", "-m", f"hermes wip: {label}")
        step("update-ref", ref, commit, "")  # "" as the old value: only if the ref doesn't exist yet
    finally:
        index.unlink(missing_ok=True)
        index.with_name(index.name + ".lock").unlink(missing_ok=True)
    return ref


def layout_ok(cfg, project=None):
    """Refuse when .worktrees, its .trash or .kept, or .worktrees/<project> is a symlink or not a directory."""
    top = cfg.root / WORKTREES
    for path in (top, top / TRASH, top / KEPT, *([top / project] if project else [])):
        if path.is_symlink() or (os.path.lexists(path) and not path.is_dir()):
            raise Refusal(f"{path} is a symlink or not a directory; ask manjo to check it.")


def inside_worktrees(cfg, path):
    """`path` (which may itself be a symlink) must sit inside the real .worktrees."""
    top = real(cfg.root / WORKTREES)
    parent = real(os.path.dirname(os.path.normpath(path)))
    if parent != top and not parent.startswith(top + os.sep):
        raise Refusal(f"{path} is not inside {cfg.root / WORKTREES}; refusing to move it.")


def move_into(cfg, path, bucket):
    layout_ok(cfg)
    inside_worktrees(cfg, path)
    folder = cfg.root / WORKTREES / bucket
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{Path(path).name}-{secrets.token_hex(4)}"
    os.rename(path, target)
    return target


def prune(cfg, project):
    base = base_path(cfg, project)
    if (base / ".git").exists():
        run_git(cfg, base, "worktree", "prune")


def trash(cfg, project, path):
    """Delete a tree that holds nothing to keep: one rename now, the files after the lock is released."""
    move_into(cfg, path, TRASH)
    prune(cfg, project)


def _force_remove(function, path, _error):
    # Read-only trees (Go's module cache, copied store paths) need write access to delete.
    try:
        os.chmod(os.path.dirname(path), 0o700)
        if not os.path.islink(path):
            os.chmod(path, 0o700)
        function(path)
    except OSError:
        pass


def empty_trash(cfg):
    top = cfg.root / WORKTREES
    folder = top / TRASH
    if top.is_symlink() or folder.is_symlink() or not folder.is_dir():
        return
    for entry in list(folder.iterdir()):
        if real(entry.parent) != real(folder):
            continue
        try:
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry, onexc=_force_remove)
            else:
                entry.unlink(missing_ok=True)
        except OSError as error:
            print(f"warning: could not delete {entry}: {error}", file=sys.stderr)


def add_worktree(cfg, base, path, branch, *args):
    """`git worktree add`; a non-zero exit after a complete checkout (a failing hook) is a warning."""
    result = run_git(cfg, base, "worktree", "add", "-q", *args)
    if result.returncode == 0:
        return []
    detail = result.stderr.strip().splitlines()[-3:] or ["no output"]
    entry = entry_for(worktree_entries(cfg, base), path)
    if entry is not None and entry.get("branch") == f"refs/heads/{branch}" and "locked" not in entry:
        return [f"git worktree add exited {result.returncode} after the checkout: " + " / ".join(detail)]
    raise Refusal(f"git worktree add failed in {base}: {detail[-1]}")


def plan_worktree(cfg, tasks, task, branch, follow_up):
    """Checks under the lock; returns what make_worktree runs without it."""
    base = base_path(cfg, task["project"])
    path = worktree_path(cfg, task["project"], task["task_id"])
    layout_ok(cfg, task["project"])
    check_base(cfg, base)
    git_out(cfg, base, "worktree", "prune", what="git worktree prune")
    entries = worktree_entries(cfg, base)
    ref, remote_ref = f"refs/heads/{branch}", f"refs/remotes/{PR_REMOTE}/{branch}"
    mine = entry_for(entries, path)
    if mine is not None:
        if "locked" in mine:
            raise Refusal(f"{path} is a locked worktree; ask manjo to check it.")
        if mine.get("branch") == ref:
            return {"action": "adopt", "detach": False, "start_sha": None}  # an interrupted task-branch got this far
        raise Refusal(f"{path} is a worktree on another branch; ask manjo to check it.")
    if os.path.lexists(path):
        # Not a worktree of this base: never ours to delete.
        if path.is_dir() and not path.is_symlink() and not any(path.iterdir()):
            path.rmdir()
        else:
            keep_aside(cfg, task["project"], path)
    plan = {"action": None, "detach": False}
    holder = next((entry for entry in entries if entry.get("branch") == ref), None)
    if holder is not None:
        if real(holder["path"]) != real(base):
            owner = next((t["task_id"] for t in tasks if t["worktree"] and real(t["worktree"]) == real(holder["path"])),
                         None)
            raise Refusal(f"Branch {branch} is checked out in {holder['path']}"
                          + (f" (task {owner})" if owner else "") + "; ask manjo.")
        if any(t["legacy"] and t["project"] == task["project"] for t in tasks):
            raise Refusal(f"Branch {branch} is checked out in the base clone {base}, where an older task still works.")
        if uncommitted(cfg, base):
            raise Refusal(f"Branch {branch} is checked out in the base clone {base}, which has uncommitted changes; "
                          "ask manjo.")
        plan["detach"] = True
    local, remote = ref_exists(cfg, base, ref), ref_exists(cfg, base, remote_ref)
    if follow_up:
        if not remote:
            raise Refusal(f"No {PR_REMOTE}/{branch}: fetch {PR_REMOTE} first, or drop --follow-up for a new branch.")
        if local and run_git(cfg, base, "merge-base", "--is-ancestor", ref, remote_ref).returncode != 0:
            raise Refusal(f"Local {branch} has commits that aren't on {PR_REMOTE}/{branch} (diverged or unpushed); "
                          "ask manjo.")
        plan.update(action="existing" if local else "track", start=remote_ref)
    else:
        if local or remote:
            where = " and ".join(part for part, there in (("locally", local), (f"on {PR_REMOTE}", remote)) if there)
            raise Refusal(f"Branch {branch} already exists {where}; for a review follow-up add --follow-up, "
                          "otherwise pick another name.")
        prefix = f"refs/remotes/{cfg.base_remote}/"
        head = run_git(cfg, base, "symbolic-ref", "-q", f"{prefix}HEAD").stdout.strip()
        if not head.startswith(prefix) or run_git(cfg, base, "rev-parse", "--verify", "-q",
                                                  f"{head}^{{commit}}").returncode:
            raise Refusal(f"Unknown default branch: fetch {cfg.base_remote}, then run "
                          f"`git remote set-head {cfg.base_remote} --auto` in {base}.")
        plan.update(action="new", start=head)
    plan["start_sha"] = git_out(cfg, base, "rev-parse", "--verify", f"{plan['start']}^{{commit}}", what="git rev-parse")
    return plan


def make_worktree(cfg, project, path, branch, plan):
    """The slow part, without the lock: check out the task's worktree. Returns warnings."""
    base = base_path(cfg, project)
    action = plan["action"]
    if action == "adopt":
        return []
    path.parent.mkdir(parents=True, exist_ok=True)
    layout_ok(cfg, project)
    if plan["detach"]:
        git_out(cfg, base, "checkout", "-q", "--detach", what="git checkout --detach")
    if action == "new":
        # No tracking: a branch tracking <base remote>/<default> would make a bare `git push` target it.
        return add_worktree(cfg, base, path, branch, "--no-track", "-b", branch, str(path), plan["start"])
    if action == "track":
        return add_worktree(cfg, base, path, branch, "--track", "-b", branch, str(path), plan["start"])
    warnings = add_worktree(cfg, base, path, branch, str(path), branch)
    git_out(cfg, path, "merge", "-q", "--ff-only", plan["start"], what="git merge --ff-only")
    git_out(cfg, path, "branch", "-q", f"--set-upstream-to={PR_REMOTE}/{branch}", what="git branch")
    return warnings


# --- commands ---------------------------------------------------------------


def view(task):
    data = {"task_id": task["task_id"], "origin_kind": origin_kind(task)}
    if origin_kind(task) == "matrix":
        data.update(room=task["room"], thread=task["thread"])
    else:
        data["session_id"] = task["room"].removeprefix(APP_PREFIX)
    for key in ("started_at", "last_active", "project", "branch", "summary", "worktree", "legacy"):
        data[key] = task[key]
    return data


def timing(cfg, task, now):
    if task is None:
        return {"age_seconds": None, "idle_seconds": None, "possibly_stale": False}
    age = max(now - parse_time(task["started_at"]), timedelta())
    idle = max(now - parse_time(task["last_active"]), timedelta())
    return {"age_seconds": int(age.total_seconds()), "idle_seconds": int(idle.total_seconds()),
            "possibly_stale": idle > cfg.stale}


def reply(cfg, store, now, result, task, **extra):
    return {"result": result, "active": view(task) if task else None, "owned": task is not None,
            **timing(cfg, task, now), "live": len(store.tasks), "max_live": cfg.max_live, **extra}


def owned_task(store, origin, started_at):
    task = next((t for t in store.tasks if origin_of(t) == origin), None)
    if task is None or task["started_at"] != started_at:
        raise Refusal("No live task for this origin with that started_at; run task-status.")
    return task


def orphans(cfg, tasks):
    known = {real(t["worktree"]) for t in tasks if t["worktree"] and not t["legacy"]}
    found = []
    try:
        projects = sorted((cfg.root / WORKTREES).iterdir())
    except OSError:
        return found
    for project in projects:
        if project.name.startswith(".") or project.is_symlink() or not project.is_dir():
            continue
        found += [f"{project.name}/{entry.name}" for entry in sorted(project.iterdir()) if real(entry) not in known]
    return found


def listing(cfg, store, now):
    tasks = []
    for task in sorted(store.tasks, key=lambda t: t["started_at"]):
        tasks.append({
            "task_id": task["task_id"], "project": task["project"], "origin_kind": origin_kind(task),
            "branch": task["branch"], "started_at": task["started_at"], "last_active": task["last_active"],
            **{key: value for key, value in timing(cfg, task, now).items() if key != "age_seconds"},
            "legacy": task["legacy"], "worktree_exists": bool(task["worktree"]) and os.path.lexists(task["worktree"]),
            "summary": task["summary"],
        })
    return {"result": "active" if tasks else "idle", "tasks": tasks, "live": len(tasks), "max_live": cfg.max_live,
            "orphans": orphans(cfg, store.tasks), "kept": kept_trees(cfg), "wip_refs": wip_refs(cfg)}


def cmd_claim(cfg, store, now, origin, project, summary, mint_app):
    session_id = None
    if mint_app:
        while True:
            session_id = secrets.token_hex(8)
            origin = (APP_PREFIX + session_id, "")
            if all(origin_of(t) != origin for t in store.tasks):
                break
    task = next((t for t in store.tasks if origin_of(t) == origin), None)
    if task is not None:
        task["last_active"] = stamp(now)
        store.save()
        return reply(cfg, store, now, "active", task)
    if cfg.max_live is not None and len(store.tasks) >= cfg.max_live:
        return reply(cfg, store, now, "busy", None)
    task = {
        "task_id": mint_task_id(cfg, store.tasks, project), "started_at": stamp(now), "last_active": stamp(now),
        "room": origin[0], "thread": origin[1], "project": project, "branch": PENDING, "summary": summary,
        "worktree": None, "legacy": False, "preparing": False, "reservation": None,
    }
    store.tasks.append(task)
    store.save()
    # No worktree path yet: task-branch creates it, and anything put there before would be in its way.
    response = reply(cfg, store, now, "claimed", task)
    if session_id is not None:
        response["session_id"] = session_id
    return response


def cmd_branch(cfg, store, now, origin, started_at, branch, follow_up):
    task = owned_task(store, origin, started_at)
    if task["legacy"]:
        raise Refusal(f"This task predates worktrees: finish it in {task['worktree']} on {task['branch']}.")
    if task["worktree"] is not None and not task["preparing"]:
        if task["branch"] != branch:
            raise Refusal(f"This task's worktree is on {task['branch']}; to change branch, finish it with "
                          "task-done and claim a new task.")
        entry = entry_for(worktree_entries(cfg, base_path(cfg, task["project"])), task["worktree"])
        if entry is None or entry.get("branch") != f"refs/heads/{branch}":
            raise Refusal(f"{task['worktree']} is missing or not on {branch}; ask manjo for 'clear task'.")
        task["last_active"] = stamp(now)
        store.save()
        return reply(cfg, store, now, "updated", task)
    if task["preparing"]:
        if task["branch"] != branch:
            raise Refusal(f"This task is still setting up a worktree for {task['branch']}; retry that branch, or ask "
                          "manjo for 'clear task'.")
        if now - parse_time(task["reservation"]["reserved_at"]) < PREPARING_GRACE:
            # Another task-branch may still be checking out; only an older reservation is a crash to recover.
            raise Refusal("This task's worktree is still being created; retry in a few minutes.")
        recover(cfg, task, now)
    other = next((t for t in store.tasks if t is not task and t["project"] == task["project"]
                  and t["branch"] == branch), None)
    if other is not None:
        raise Refusal(f"Branch {branch} belongs to another live task ({other['task_id']}); pick another name.")
    plan = plan_worktree(cfg, store.tasks, task, branch, follow_up)
    path = worktree_path(cfg, task["project"], task["task_id"])
    nonce = secrets.token_hex(8)
    task.update(branch=branch, worktree=str(path), preparing=True, last_active=stamp(now), reservation={
        "reserved_at": stamp(now), "nonce": nonce, "action": plan["action"], "start": plan["start_sha"]})
    store.save()
    key = (task["task_id"], task["started_at"])
    store.unlock()
    warnings, failure = [], None
    try:
        warnings = make_worktree(cfg, task["project"], path, branch, plan)
    except Refusal as error:
        failure = error
    except OSError as error:
        failure = Refusal(f"Could not create {path}: {error}")
    store.lock(wait=max(RELOCK_WAIT, cfg.lock_wait))
    store.reload()
    current = next((t for t in store.tasks if (t["task_id"], t["started_at"]) == key), None)
    if current is None or (current["reservation"] or {}).get("nonce") != nonce:
        if current is not None:
            # A later task-branch recovered this reservation and owns the result: leave it alone.
            if not current["preparing"] and current["branch"] == branch and current["worktree"] == str(path):
                return reply(cfg, store, now, "updated", current)
            raise Refusal("Another task-branch took over this task's worktree setup; run task-status.")
        undo(cfg, task["project"], path, branch, plan, now)
        raise failure or Refusal("The task was cleared while its worktree was being created; the worktree is removed.")
    if failure is not None:
        undo(cfg, current["project"], path, branch, plan, now)
        current.update(branch=PENDING, worktree=None, preparing=False, reservation=None)
        store.save()
        raise failure
    current.update(preparing=False, reservation=None, last_active=stamp(now))
    store.save()
    response = reply(cfg, store, now, "updated", current)
    if warnings:
        response["warnings"] = warnings
    return response


def keep_aside(cfg, project, path, linked=False):
    """Move a tree into .worktrees/.kept instead of deleting it. A linked worktree stays registered and
    locked, so its admin dir (index, HEAD, a submodule's objects) is never pruned."""
    base = base_path(cfg, project)
    if linked:
        run_git(cfg, base, "worktree", "lock", "--reason", "kept aside by the Hermes task tools", str(path))
    target = move_into(cfg, path, KEPT)
    if linked:
        run_git(cfg, base, "worktree", "repair", str(target))
    else:
        prune(cfg, project)
    return str(target)


def linked_entry(cfg, base, path):
    """Git's entry for `path` when it is a linked worktree of this base clone (not the base itself), else None."""
    if os.path.islink(path) or not os.path.isdir(path) or not (base / ".git").exists():
        return None
    entry = entry_for(worktree_entries(cfg, base), path)
    if entry is None or real(entry["path"]) == real(base):
        return None
    mine = run_git(cfg, path, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir")
    theirs = run_git(cfg, base, "rev-parse", "--path-format=absolute", "--git-common-dir")
    lines = mine.stdout.splitlines()
    if mine.returncode or theirs.returncode or len(lines) != 2:
        return None
    if real(lines[0]) != real(path) or real(lines[1]) != real(theirs.stdout.strip()):
        return None
    return entry


def git_lines(cfg, path, *args):
    result = run_git(cfg, path, *args)
    if result.returncode != 0:
        raise Refusal(f"git {args[0]} failed in {path}")
    return result.stdout.splitlines()


def risks(cfg, path):
    """What deleting a linked worktree could lose. Raises Refusal when Git can't tell."""
    paths = git_lines(cfg, path, "rev-parse", "--path-format=absolute", "--git-path", "modules",
                      *[arg for name in IN_PROGRESS for arg in ("--git-path", name)])
    if len(paths) != 1 + len(IN_PROGRESS):
        raise Refusal(f"unexpected git rev-parse output in {path}")
    submodules = run_git(cfg, path, "submodule", "status")
    status = git_lines(cfg, path, "status", "--porcelain", "--untracked-files=all")
    flags = git_lines(cfg, path, "ls-files", "-v")
    return {
        "submodules": os.path.lexists(paths[0]) or submodules.returncode != 0 or bool(submodules.stdout.strip()),
        "detached": run_git(cfg, path, "symbolic-ref", "-q", "HEAD").returncode != 0,
        "in_progress": [name for name, state in zip(IN_PROGRESS, paths[1:]) if os.path.lexists(state)],
        # Commits only this worktree's HEAD (and its reflog, which goes with it) holds.
        "unreachable": bool(git_lines(cfg, path, "rev-list", "-n", "1", "HEAD", "--not", "--branches", "--remotes",
                                      "--tags")),
        "changes": len(status),
        # An untracked nested repository shows as its directory; a snapshot would hold only a gitlink.
        "nested": any(line.startswith("?? ") and line.rstrip('"').endswith("/") for line in status),
        # skip-worktree (S) or assume-unchanged (lowercase) entries hide edits from `git status`.
        "hidden": any(line[:1] == "S" or line[:1].islower() for line in flags),
    }


def remove_tree(cfg, project, path, *, clear, now, wip_name, label, reservation=None):
    """Remove a worktree directory; returns (wip_ref, kept, removed).

    Deletes only a linked worktree of the project's base clone, and only once nothing in it would be
    lost (task-done) or it is saved to a wip ref (task-clear). task-done refuses what the agent can
    fix; anything else (another kind of tree, submodules, nested repos, hidden edits, a tree Git
    can't read) is kept aside in .worktrees/.kept. Ignored files are not kept.
    """
    base = base_path(cfg, project)
    path = Path(path)
    if not os.path.lexists(path):
        prune(cfg, project)  # deleted by hand: drop Git's record of it
        return None, None, False
    layout_ok(cfg, project)
    if path.is_symlink():
        trash(cfg, project, path)  # only the link goes
        return None, None, True
    entry = entry_for(worktree_entries(cfg, base), path) if (base / ".git").exists() else None
    if entry is not None and "locked" in entry:
        if (entry["locked"] == "initializing" and reservation is not None
                and now - parse_time(reservation["reserved_at"]) >= STALE_INIT):
            run_git(cfg, base, "worktree", "unlock", str(path))  # a killed checkout, never worked in
            return None, keep_aside(cfg, project, path), False
        raise Refusal(f"{path} is a locked worktree; ask manjo to check it "
                      f"(git -C '{base}' worktree unlock '{path}').")
    if linked_entry(cfg, base, path) is None:
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()
            prune(cfg, project)
            return None, None, True
        return None, keep_aside(cfg, project, path), False
    try:
        found = risks(cfg, path)
    except Refusal:
        if not clear:
            raise
        return None, keep_aside(cfg, project, path, linked=True), False
    if not clear:
        if found["submodules"]:
            raise Refusal(f"{path} has submodules; ask manjo.")
        if found["in_progress"]:  # before `detached`: a rebase detaches HEAD
            raise Refusal(f"{path}: a {'/'.join(found['in_progress'])} is in progress; finish or abort it first.")
        if found["detached"]:
            raise Refusal(f"{path}: HEAD is not on a branch. Put what you need on the task's branch and check it "
                          "out, or ask manjo.")
        if found["unreachable"]:
            raise Refusal(f"{path} has commits that no branch, remote or tag holds; ask manjo.")
        if found["changes"]:
            raise Refusal(f"{path} has {found['changes']} uncommitted change(s): commit or discard them first, "
                          "or ask manjo for 'clear task'.")
        if found["hidden"]:
            return None, keep_aside(cfg, project, path, linked=True), False
        trash(cfg, project, path)
        return None, None, True
    if found["submodules"] or found["nested"] or found["hidden"]:
        return None, keep_aside(cfg, project, path, linked=True), False
    ref = None
    if found["changes"] or found["unreachable"] or found["in_progress"]:
        try:
            ref = snapshot(cfg, path, wip_name, label)
        except Refusal:
            return None, keep_aside(cfg, project, path, linked=True), False
    trash(cfg, project, path)
    return ref, None, True


def drop_branch_at(cfg, base, branch, sha):
    """Delete refs/heads/<branch> only while it is exactly `sha` and checked out nowhere."""
    ref = f"refs/heads/{branch}"
    tip = run_git(cfg, base, "rev-parse", "-q", "--verify", f"{ref}^{{commit}}")
    if not sha or tip.returncode or tip.stdout.strip() != sha:
        return False
    if any(entry.get("branch") == ref for entry in worktree_entries(cfg, base)):
        return False
    return run_git(cfg, base, "update-ref", "-d", ref, sha).returncode == 0


def drop_pushed_branch(cfg, project, branch):
    """After task-done: delete the local branch when origin has exactly it. Nothing is lost, and a later
    follow-up tracks origin afresh even if the PR branch was rewritten."""
    base = base_path(cfg, project)
    if branch == PENDING or not (base / ".git").exists():
        return False
    remote = run_git(cfg, base, "rev-parse", "-q", "--verify", f"refs/remotes/{PR_REMOTE}/{branch}^{{commit}}")
    return remote.returncode == 0 and drop_branch_at(cfg, base, branch, remote.stdout.strip())


def recover(cfg, task, now):
    """An old reservation is a crashed task-branch: clear what it left, so the plan starts clean."""
    base = base_path(cfg, task["project"])
    path = Path(task["worktree"])
    reservation = task["reservation"]
    if not (base / ".git").exists():
        return
    layout_ok(cfg, task["project"])
    entry = entry_for(worktree_entries(cfg, base), path)
    if (entry is not None and entry.get("locked") == "initializing"
            and now - parse_time(reservation["reserved_at"]) >= STALE_INIT):
        run_git(cfg, base, "worktree", "unlock", str(path))  # a killed checkout, never worked in
        if os.path.lexists(path):
            keep_aside(cfg, task["project"], path)
        else:
            prune(cfg, task["project"])
        entry = None
    if entry is None and reservation["action"] in ("new", "track"):
        # `git worktree add -b` makes the branch first and leaves it when the checkout dies.
        drop_branch_at(cfg, base, task["branch"], reservation["start"])


def undo(cfg, project, path, branch, plan, now):
    """After a failed or orphaned checkout: remove what this run made, never anything else."""
    try:
        if plan["action"] != "adopt" and os.path.lexists(path):
            remove_tree(cfg, project, path, clear=True, now=now, wip_name=path.name,
                        label=f"interrupted task-branch {branch}")
        if plan["action"] in ("new", "track"):
            drop_branch_at(cfg, base_path(cfg, project), branch, plan["start_sha"])
    except (Refusal, OSError) as error:
        print(f"warning: could not clean up after task-branch: {error}", file=sys.stderr)


def kept_trees(cfg):
    folder = cfg.root / WORKTREES / KEPT
    if folder.is_symlink() or not folder.is_dir():
        return []
    return sorted(entry.name for entry in folder.iterdir())


def wip_refs(cfg):
    refs = []
    try:
        repos = sorted(cfg.root.iterdir())
    except OSError:
        return refs
    for repo in repos:
        if repo.name.startswith(".") or repo.is_symlink() or not (repo / ".git").exists():
            continue
        out = run_git(cfg, repo, "for-each-ref", "--format=%(refname)", "refs/hermes/wip/")
        if out.returncode == 0:
            refs += [{"project": repo.name, "ref": ref} for ref in out.stdout.split()]
    return refs


def release(cfg, store, task, now, *, clear):
    """Remove a task's worktree (if any) and its record; returns (wip ref, kept path, removed, branch deleted)."""
    ref = kept = None
    removed = deleted = False
    if task["worktree"] is not None and not task["legacy"]:
        ref, kept, removed = remove_tree(
            cfg, task["project"], task["worktree"], clear=clear, now=now, wip_name=task["task_id"],
            label=f"task {task['task_id']} ({task['branch']})", reservation=task["reservation"])
        if not clear and kept is None:
            deleted = drop_pushed_branch(cfg, task["project"], task["branch"])
    store.tasks.remove(task)
    store.save()
    return ref, kept, removed, deleted


def cmd_done(cfg, store, now, origin, started_at):
    task = owned_task(store, origin, started_at)
    if task["preparing"]:
        raise Refusal("This task's worktree is still being created; retry in a moment, or ask manjo for "
                      "'clear task' if that persists.")
    _, kept, removed, deleted = release(cfg, store, task, now, clear=False)
    return reply(cfg, store, now, "done", None, task_id=task["task_id"], project=task["project"],
                 branch=task["branch"], worktree_removed=removed, kept=kept, branch_deleted=deleted)


def cmd_clear(cfg, store, now, origin, target):
    if origin is not None:
        task = next((t for t in store.tasks if origin_of(t) == origin), None)
        if task is None:
            raise Refusal("No live task for this origin.")
    else:
        task = next((t for t in store.tasks if t["task_id"] == target), None)
    if task is not None:
        ref, kept, removed, _ = release(cfg, store, task, now, clear=True)
        return {"result": "cleared", "task_id": task["task_id"], "project": task["project"], "branch": task["branch"],
                "wip_ref": ref, "kept": kept, "worktree_removed": removed, "live": len(store.tasks),
                "max_live": cfg.max_live}
    project, _, name = (target or "").partition("/")
    if not (PROJECT.fullmatch(project) and ORPHAN.fullmatch(name)) or target not in orphans(cfg, store.tasks):
        raise Refusal("No live task or orphaned worktree with that ID; see task-status --all.")
    ref, kept, removed = remove_tree(
        cfg, project, cfg.root / WORKTREES / project / name, clear=True, now=now,
        wip_name=name if TASK_ID.fullmatch(name) else f"orphan-{secrets.token_hex(4)}",
        label=f"orphaned worktree {target}")
    return {"result": "cleared", "orphan": target, "wip_ref": ref, "kept": kept, "worktree_removed": removed,
            "live": len(store.tasks), "max_live": cfg.max_live}


def worktree_main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="action", required=True)
    status = commands.add_parser("task-status")
    status.add_argument("--all", action="store_true", help="list every live task and orphaned worktree")
    claim = commands.add_parser("task-claim")
    branch = commands.add_parser("task-branch")
    done = commands.add_parser("task-done")
    clear = commands.add_parser("task-clear")
    target = clear.add_mutually_exclusive_group()
    target.add_argument("--id", metavar="TASK_ID", help="a task_id or orphan from task-status --all")
    target.add_argument("--repair", action="store_true", help="move invalid task state aside")
    for command in (status, claim, branch, done, clear):
        command.add_argument("--app", metavar="ID", help="app task ID ('new' to claim)")
        command.add_argument("room", nargs="?")
        command.add_argument("thread", nargs="?")
    claim.add_argument("project", type=project_name)
    claim.add_argument("summary", choices=("-",), help="read the summary from stdin")
    for command in (branch, done):
        command.add_argument("started_at")
    branch.add_argument("branch", type=clean)
    branch.add_argument("--follow-up", action="store_true", help="the existing PR branch, from origin")
    argv = sys.argv[1:]
    if argv in (["task-status", "--"], ["task-clear", "--"]):
        argv.pop()
    args = parser.parse_args(argv)
    action = args.action
    origin = None
    mint_app = False
    given = args.app is not None or args.room is not None or args.thread is not None
    if action == "task-status" and args.all and given:
        parser.exit(2, "Use --all without an origin.\n")
    if action == "task-clear":
        if (args.id is not None or args.repair) == given:
            parser.exit(2, "Name a task: an origin (this conversation's task), --id TASK_ID, or --repair.\n")
    if given or action in ("task-claim", "task-branch", "task-done"):
        if args.app is not None:
            if args.room is not None or args.thread is not None:
                parser.exit(2, "Use either --app or Matrix room and thread IDs.\n")
            if action == "task-claim":
                if args.app != "new":
                    parser.exit(2, "Use --app new to claim a new app task.\n")
                mint_app = True
            elif not APP_ID.fullmatch(args.app):
                parser.exit(2, "Invalid app task ID.\n")
            else:
                origin = (APP_PREFIX + args.app, "")
        else:
            if not ROOM_ID.fullmatch(args.room or ""):
                parser.exit(2, "Invalid Matrix room ID.\n")
            if not THREAD_ID.fullmatch(args.thread or ""):
                parser.exit(2, "Invalid Matrix thread/event ID.\n")
            origin = (args.room, args.thread)
    cfg = worktree_config(parser)
    allowed_projects = env_list(parser, "HERMES_TASK_PROJECTS")
    allowed_rooms = env_list(parser, "HERMES_TASK_ROOMS")
    app_only = env_list(parser, "HERMES_TASK_APP_ONLY_PROJECTS")
    pattern = branch_pattern(parser)
    if allowed_rooms is not None and origin is not None and not origin[0].startswith(APP_PREFIX):
        if origin[0] not in allowed_rooms:
            parser.exit(2, "This Matrix room does not use these task commands.\n")
    if action == "task-branch":
        if pattern is not None and not pattern.fullmatch(args.branch):
            parser.exit(2, "Branch name does not match the required pattern.\n")
        if (args.branch == PENDING or args.branch.startswith("-") or subprocess.run(
                [cfg.git, "check-ref-format", f"refs/heads/{args.branch}"], capture_output=True,
                env=git_env(), check=False).returncode != 0):
            parser.exit(2, "Invalid branch name.\n")
    summary = None
    if action == "task-claim":
        if mint_app and args.project not in app_projects(parser):
            parser.exit(2, "Project is not enabled for app tasks.\n")
        if not mint_app and app_only is not None and args.project in app_only:
            parser.exit(2, "Project is app-only; claim it from the Hermes app.\n")
        if allowed_projects is not None and args.project not in allowed_projects:
            parser.exit(2, "Project is not enabled for these task commands.\n")
        try:
            summary = clean(sys.stdin.read())
        except argparse.ArgumentTypeError as error:
            parser.exit(2, f"Invalid task summary: {error}.\n")

    cfg.state.mkdir(parents=True, exist_ok=True)
    store = Store(cfg)
    store.lock()
    try:
        now = datetime.now(UTC)
        repair = action == "task-clear" and args.repair
        moved = []
        try:
            store.tasks = load_live(cfg)
        except ValueError as error:
            if not repair:
                raise Refusal(f"Invalid task state in {STATE_FILE} ({error}); ask manjo for 'clear task' (task-clear --repair).") from None
            backup = cfg.state / f"{STATE_FILE}.bad-{now.strftime('%Y%m%dT%H%M%S%fZ')}"
            (cfg.state / STATE_FILE).rename(backup)
            moved.append(backup.name)
            store.tasks = []
        store.tasks = adopt_legacy(cfg, store.tasks, now, repair, moved)
        if action == "task-status":
            if args.all:
                response = listing(cfg, store, now)
            elif origin is None:
                response = {"result": "active" if store.tasks else "idle", "live": len(store.tasks),
                            "max_live": cfg.max_live}
            else:
                task = next((t for t in store.tasks if origin_of(t) == origin), None)
                if task is not None:
                    task["last_active"] = stamp(now)
                    store.save()
                response = reply(cfg, store, now, "active" if task else "none", task)
        elif action == "task-claim":
            response = cmd_claim(cfg, store, now, origin, args.project, summary, mint_app)
        elif action == "task-branch":
            response = cmd_branch(cfg, store, now, origin, args.started_at, args.branch, args.follow_up)
        elif action == "task-done":
            response = cmd_done(cfg, store, now, origin, args.started_at)
        elif args.repair:
            response = {"result": "repaired" if moved else "ok", "moved": moved, "live": len(store.tasks),
                        "max_live": cfg.max_live}
        else:
            response = cmd_clear(cfg, store, now, origin, args.id)
    except Refusal as error:
        store.unlock()
        empty_trash(cfg)
        print(error, file=sys.stderr)
        sys.exit(2)
    except OSError as error:
        # Never a bare traceback: say what failed (state is written atomically, so it is whole either way).
        store.unlock()
        print(f"Task command failed: {error}; run task-status before retrying.", file=sys.stderr)
        sys.exit(2)
    store.unlock()
    print(json.dumps(response), flush=True)
    empty_trash(cfg)


def main():
    mode = os.environ.get("HERMES_TASK_MODE")
    if mode is None:
        slot_main()
    elif mode == "worktrees":
        worktree_main()
    else:
        print("HERMES_TASK_MODE must be 'worktrees' or unset.", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
