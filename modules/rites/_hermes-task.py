"""Stygies task state. The launcher holds .task-lock for this entire process."""

import argparse
import json
import re
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import NamedTuple


ROOM_ID = re.compile(r"!(?:[^\s:]+:\S+|[A-Za-z0-9_-]+)")
THREAD_ID = re.compile(r"\$[A-Za-z0-9_+/=-]+")


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


def clean(text):
    text = re.sub(r"[\t\r\n]+", " ", text).strip()
    if not text:
        raise argparse.ArgumentTypeError("task fields must not be empty")
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
        if not ROOM_ID.fullmatch(task.room) or not THREAD_ID.fullmatch(task.thread):
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


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("task-status")
    commands.add_parser("task-clear")
    claim = commands.add_parser("task-claim")
    done = commands.add_parser("task-done")
    branch = commands.add_parser("task-branch")
    for command in (claim, done, branch):
        command.add_argument("room")
        command.add_argument("thread")
    claim.add_argument("project", type=clean)
    claim.add_argument("summary", choices=("-",), help="read the summary from stdin")
    for command in (done, branch):
        command.add_argument("started_at")
    branch.add_argument("branch", type=clean)
    argv = sys.argv[1:]
    if argv in (["task-status", "--"], ["task-clear", "--"]):
        argv.pop()
    args = parser.parse_args(argv)
    action = args.action
    if action in ("task-claim", "task-done", "task-branch"):
        if not ROOM_ID.fullmatch(args.room):
            parser.exit(2, "Invalid Matrix room ID.\n")
        if not THREAD_ID.fullmatch(args.thread):
            parser.exit(2, "Invalid Matrix thread/event ID.\n")
    if action == "task-claim":
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

    if action == "task-status":
        result = "active" if active else "idle"
    elif action == "task-claim":
        origin = (args.room, args.thread)
        if active is None:
            if queue:
                parser.exit(2, "Queue exists without an active task; ask manjo for 'clear task'.\n")
            active = Task(stamp, *origin, args.project, "pending", summary)
            write_tasks(current_path, [active])
            result = "claimed"
        elif active.origin == origin:
            result = "active"
        else:
            position = next((i for i, task in enumerate(queue, 1) if task.origin == origin), None)
            if position is None:
                queue.append(Task(stamp, *origin, args.project, "pending", summary))
                write_tasks(queue_path, queue)
                position = len(queue)
            result = "queued"
    else:
        if action != "task-clear" and (
            active is None or (args.room, args.thread, args.started_at) != (*active.origin, active.started_at)
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
    print(json.dumps({
        "result": result,
        "active": active._asdict() if active else None,
        "age_seconds": int(age.total_seconds()) if age is not None else None,
        "possibly_stale": age is not None and age > timedelta(hours=12),
        "queue_position": position,
    }))


if __name__ == "__main__":
    main()
