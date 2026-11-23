"""Stygies task state. The launcher holds .task-lock for this entire process."""

import argparse
import json
import re
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import NamedTuple


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
        lines = path.read_text(encoding="utf-8").rstrip("\n").split("\n")
        return [Task(*line.split("\t")) for line in lines if line]
    except FileNotFoundError:
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
        command.add_argument("room", type=clean)
        command.add_argument("thread", type=clean)
    claim.add_argument("project", type=clean)
    claim.add_argument("summary", type=clean)
    for command in (done, branch):
        command.add_argument("started_at")
    branch.add_argument("branch", type=clean)
    args = parser.parse_args()

    work = Path.home() / "work"
    current_path = work / ".current-task"
    queue_path = work / ".task-queue"
    current = read_tasks(current_path)
    active = current[0] if current else None
    queue = read_tasks(queue_path)
    # Promotion writes the slot first. If interrupted before trimming the queue,
    # the promoted task is already active, not another task to start.
    if active and queue and active.origin == queue[0].origin:
        queue.pop(0)
    now = datetime.now(UTC)
    stamp = now.isoformat().replace("+00:00", "Z")
    action = args.action
    position = None

    if action == "task-status":
        result = "active" if active else "idle"
    elif action == "task-claim":
        origin = (args.room, args.thread)
        if active is None:
            if queue:
                parser.error("queue exists without an active task; use task-clear to advance it")
            active = Task(stamp, *origin, args.project, "pending", args.summary)
            write_tasks(current_path, [active])
            result = "claimed"
        elif active.origin == origin:
            result = "active"
        else:
            position = next((i for i, task in enumerate(queue, 1) if task.origin == origin), None)
            if position is None:
                queue.append(Task(stamp, *origin, args.project, "pending", args.summary))
                write_tasks(queue_path, queue)
                position = len(queue)
            result = "queued"
    else:
        if action != "task-clear" and (
            active is None or (args.room, args.thread, args.started_at) != (*active.origin, active.started_at)
        ):
            parser.error("task no longer owns the slot")
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
