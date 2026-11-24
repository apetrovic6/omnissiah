"""Stygies task state. The launcher holds .task-lock for this entire process."""

import argparse
import json
import os
import re
import secrets
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import NamedTuple


ROOM_ID = re.compile(r"!(?:[^\s:]+:\S+|[A-Za-z0-9_-]+)")
THREAD_ID = re.compile(r"\$[A-Za-z0-9_+/=-]+")
APP_PREFIX = "app:"
APP_ID = re.compile(r"[0-9a-f]{16}")
PROJECT = re.compile(r"[A-Za-z0-9._-]+")


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
    if not PROJECT.fullmatch(text) or text in (".", ".."):
        raise argparse.ArgumentTypeError("expected a repository basename")
    return text


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


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="action", required=True)
    status = commands.add_parser("task-status")
    status.add_argument("--queue", action="store_true", help="list queued projects and positions")
    commands.add_parser("task-clear")
    drop = commands.add_parser("task-drop")
    drop.add_argument("position", type=int)
    drop.add_argument("project")
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
    list_queue = action == "task-status" and args.queue
    if list_queue and origin is not None:
        parser.exit(2, "Use --queue without an origin.\n")
    if action == "task-claim":
        if mint_app and args.project not in json.loads(os.environ.get("HERMES_TASK_APP_PROJECTS", "[]")):
            parser.exit(2, "Project is not enabled for app tasks.\n")
        try:
            summary = clean(sys.stdin.read())
        except argparse.ArgumentTypeError as error:
            parser.exit(2, f"Invalid task summary: {error}.\n")

    work = Path.home() / "work"
    current_path = work / ".current-task"
    queue_path = work / ".task-queue"
    now = datetime.now(UTC)
    stamp = now.isoformat().replace("+00:00", "Z")
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
            active = Task(stamp, *origin, args.project, "pending", summary)
            write_tasks(current_path, [active])
            result = "claimed"
        elif active.origin == origin:
            result = "active"
        else:
            position = None if mint_app else queue_position(queue, origin)
            if position is None:
                queue.append(Task(stamp, *origin, args.project, "pending", summary))
                write_tasks(queue_path, queue)
                position = len(queue)
            result = "queued"
    elif action == "task-drop":
        if not 1 <= args.position <= len(queue) or queue[args.position - 1].project != args.project:
            parser.exit(2, "No queued task matches that position and project.\n")
        del queue[args.position - 1]
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
        response["queue"] = [
            {"queue_position": i, "origin_kind": task.kind, "project": task.project}
            for i, task in enumerate(queue, 1)
        ]
    if session_id is not None:
        response["session_id"] = session_id
    print(json.dumps(response))


if __name__ == "__main__":
    main()
