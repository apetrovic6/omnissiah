"""One-time move of Hermes's stygies workspaces to the 2026-11 layout. Idempotent; run as hermes.

    old                                  new
    ~/work (personal repos, slot)    ->  ~/personal
    ~/work-devzero/{<company>,.tasks} -> ~/work

Usage: _hermes-workspace-migrate.py HOME COMPANY...  (COMPANY: every name in _work-projects.nix)

Runs from stygies's activation (and by hand as `hermes-workspace-migrate`), before tmpfiles
creates the new directories, but tolerates the empty skeleton tmpfiles leaves after a refused
run: a tree of empty directories is not state.

It acts only on evidence of the old layout: ~/work-devzero, which every old generation created.
Without it, or once ~/.local/state/hermes-workspace-migrate.done exists (written, with a log
line, once ~/work-devzero is gone: after a success, or on first sight of a home without it), it
does nothing. Except: no ~/work-devzero but the old personal slot files at the top of ~/work
refuses, since that is the old layout with its evidence missing. It plans both
moves and every Git path rewrite before doing anything, and refuses (changes nothing) when the
state is ambiguous or unreadable, a slot being moved has an active task, a task command holds a
slot lock, or a hermes process has its cwd in a tree being moved (checked again right before
the renames).

Exit status: 0 nothing to do or migrated, 3 refused, 1 unexpected error. The caller never fails
the deploy on it.
"""

import fcntl
import json
import os
import sys
import time
from contextlib import ExitStack
from pathlib import Path
from tempfile import NamedTemporaryFile

TAG = "hermes-workspace-migrate"
REFUSED = 3
LOCK_WAIT = 10
STAMP = ".local/state/hermes-workspace-migrate.done"
# Injectable for tests (a fake /proc tree).
PROC = Path("/proc")


class Refused(Exception):
    pass


def log(message):
    print(f"{TAG}: {message}", file=sys.stderr, flush=True)


def has_content(path):
    """True when ``path`` is, or holds anywhere below it, anything but a directory (symlinks count).

    Raises OSError for an unreadable directory: the caller refuses rather than guess."""
    if path.is_symlink() or not path.is_dir():
        return path.exists() or path.is_symlink()
    with os.scandir(path) as entries:
        return any(not entry.is_dir(follow_symlinks=False) or has_content(Path(entry.path)) for entry in entries)


def prune_empty(path):
    """Remove a tree of empty directories (tmpfiles' skeleton). Only call when has_content is False."""
    if not path.is_dir() or path.is_symlink():
        return
    for child in path.iterdir():
        prune_empty(child)
    path.rmdir()


def classify_work(work, markers):
    """What ~/work holds: empty, personal (old layout), work (new layout) or mixed."""
    if not has_content(work):
        return "empty"
    entries = [entry for entry in work.iterdir() if has_content(entry)]
    company = [entry for entry in entries if entry.name in markers]
    if company and len(company) < len(entries):
        return "mixed"
    return "work" if company else "personal"


def company_slots(old_work):
    tasks = old_work / ".tasks"
    return sorted(path for path in tasks.iterdir() if path.is_dir() and not path.is_symlink()) if tasks.is_dir() else []


def active(slot):
    try:
        if (slot / ".current-task").read_text(encoding="utf-8").strip():
            return True
    except FileNotFoundError:
        pass
    # Worktree mode's state (_hermes-task.py): live tasks, or anything unreadable, count as active.
    try:
        tasks = json.loads((slot / ".task-state.json").read_text(encoding="utf-8")).get("tasks")
    except FileNotFoundError:
        return False
    except (ValueError, AttributeError):
        return True
    return tasks != []


def lock_slots(stack, slots):
    """Hold every existing slot lock, as the task launchers' flock does. Raises Refused when busy."""
    for slot in slots:
        lock = slot / ".task-lock"
        if not lock.is_file() or lock.is_symlink():
            continue
        stream = stack.enter_context(lock.open("rb"))
        deadline = time.monotonic() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    raise Refused(f"a task command holds {lock}; retry when it finishes") from None
                time.sleep(0.2)


def under(path, root):
    path, root = os.path.normpath(path), os.path.normpath(root)
    return path == root or path.startswith(root + "/")


def own_lineage():
    """This process and its ancestors (read from PROC), which may legitimately sit in the trees."""
    pids, pid = set(), os.getpid()
    while pid > 1 and pid not in pids:
        pids.add(pid)
        try:
            stat = (PROC / str(pid) / "stat").read_text()
            pid = int(stat.rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return pids


def processes_in(trees):
    """`pid (command)` of every process of this user whose cwd is in one of ``trees``."""
    found, uid, skip = [], os.getuid(), own_lineage()
    try:
        entries = list(PROC.iterdir())
    except OSError:
        return found
    for entry in entries:
        if not entry.name.isdigit() or int(entry.name) in skip:
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            cwd = os.readlink(entry / "cwd")
        except OSError:
            continue  # gone, or not ours to read
        if any(under(cwd, tree) for tree in trees):
            try:
                command = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
            except OSError:
                command = ""
            found.append(f"{entry.name} ({command[:60] or '?'}) in {cwd}")
    return sorted(found)


def plan(home, companies):
    old_personal = new_work = home / "work"
    new_personal = home / "personal"
    old_work = home / "work-devzero"
    for path in (new_work, new_personal, old_work):
        if path.is_symlink():
            raise Refused(f"{path} is a symlink; resolve it by hand (README, Hermes workspaces on stygies)")
    markers = set(companies) | {".tasks"}
    work_state = classify_work(new_work, markers)
    move_personal = work_state == "personal"
    move_work = has_content(old_work)
    if work_state == "mixed":
        raise Refused(f"{new_work} holds both personal entries and company/.tasks entries")
    if move_personal and has_content(new_personal):
        raise Refused(f"{old_personal} still has the old personal layout but {new_personal} is not empty")
    if move_work and work_state == "work":
        raise Refused(f"both {old_work} and {new_work} hold company state")
    slots = ([old_personal] if move_personal else []) + (company_slots(old_work) if move_work else [])
    return move_personal, move_work, slots


def gitdir_rewrites(trees, moves):
    """Every absolute Git path (linked worktrees) that names a moved location, as (file, new text).

    Collected before anything moves; the files are named by their current (old) paths. Covers
    worktree ``.git`` files inside the trees, the repos' ``worktrees/*/gitdir`` back-pointers,
    and a linked worktree's ``.git`` file outside the trees that a back-pointer names.
    Raises OSError for an unreadable directory.
    """
    def mapped(text):
        for old, new in moves:
            for prefix in (f"gitdir: {old}/", f"{old}/"):
                if text.startswith(prefix):
                    return text.replace(f"{old}/", f"{new}/", 1)
        return None

    found = {}

    def consider(path):
        try:
            text = path.read_text(encoding="utf-8")
        except (FileNotFoundError, IsADirectoryError, NotADirectoryError, UnicodeDecodeError):
            return None
        new = mapped(text)
        if new is not None:
            found[path] = new
        return text

    def walk(directory):
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                if entry.name == ".git":
                    if entry.is_file(follow_symlinks=False):
                        consider(path)  # a linked worktree: "gitdir: /abs/repo/.git/worktrees/<n>"
                    elif entry.is_dir(follow_symlinks=False):
                        for gitdir in sorted(path.glob("worktrees/*/gitdir")):
                            target = consider(gitdir)  # the back-pointer to the worktree's .git file
                            target = Path(target.strip()) if target and target.strip().startswith("/") else None
                            if target and not any(under(str(target), old) for old, _ in moves):
                                consider(target)  # a worktree outside the trees: it stays put
                        config = path / "config"
                        if config.is_file() and any(old in config.read_text(encoding="utf-8", errors="replace")
                                                    for old, _ in moves):
                            log(f"warning: {config} names an old workspace path; fix it by hand")
                elif entry.is_dir(follow_symlinks=False):
                    walk(path)

    for tree in trees:
        walk(tree)
    return found


def relocate(path, moves):
    """Where ``path`` is after the moves (a path outside them stays)."""
    text = str(path)
    for old, new in moves:
        if under(text, old):
            return Path(new + text[len(old):])
    return path


def write_text(path, text):
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        stream.write(text)
    os.chmod(stream.name, path.stat().st_mode & 0o7777)
    os.replace(stream.name, path)


def prune_stale(home):
    """An old ~/work-devzero with nothing in it (tmpfiles' last directory) goes."""
    stale = home / "work-devzero"
    if stale.is_dir() and not stale.is_symlink() and not has_content(stale):
        prune_empty(stale)
        log(f"removed the empty {stale}")


# The old personal slot's files: never at the top of ~/work in the new layout.
PERSONAL_SLOT_FILES = (".task-lock", ".task-queue", ".current-task")


def stamp(home, why):
    path = home / STAMP
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("migrated to ~/personal and ~/work\n", encoding="utf-8")
    log(f"{why}; wrote {path}, so this never runs again (README, Hermes workspaces on stygies)")


def migrate(home, companies):
    if (home / STAMP).exists():
        return 0
    old_work = home / "work-devzero"
    work, personal = home / "work", home / "personal"
    if not old_work.exists() and not old_work.is_symlink():
        # No old generation ever ran here, or the move is done: never classify ~/work again.
        # Unless ~/work still has the old personal slot: then the evidence is missing, not the old layout.
        stray = [name for name in PERSONAL_SLOT_FILES if os.path.lexists(work / name)]
        if stray:
            raise Refused(f"{work} has the old personal slot ({', '.join(stray)}) but there is no {old_work}. "
                          f"If {work} is the old personal tree, create an empty {old_work} as hermes and run "
                          "`sudo hermes-workspace-migrate` again; if not, ask manjo")
        stamp(home, f"no {old_work}: the new layout, nothing to move")
        return 0
    with ExitStack() as stack:
        try:
            move_personal, move_work, slots = plan(home, companies)
        except OSError as error:
            raise Refused(f"cannot read the workspace ({error})") from None
        if not (move_personal or move_work):
            prune_stale(home)
            if not old_work.exists():
                stamp(home, "nothing left to move")
            return 0
        lock_slots(stack, slots)
        busy = [str(slot) for slot in slots if active(slot)]
        if busy:
            raise Refused(f"active task in {', '.join(busy)}; finish or clear it, then run again")
        moves = ([(str(work), str(personal))] if move_personal else []) + (
            [(str(old_work), str(work))] if move_work else [])
        trees = [Path(old) for old, _ in moves]
        running = processes_in([work, old_work])
        if running:
            raise Refused("hermes processes have their working directory in a tree to move: "
                          + "; ".join(running) + ". Stop them (README, deploy window), then run again")
        try:
            # Re-plan under the locks: a task command may have run between the first look and the lock.
            if plan(home, companies)[:2] != (move_personal, move_work):
                raise Refused("the workspace changed while planning; run again")
            rewrites = gitdir_rewrites(trees, moves)
        except OSError as error:
            raise Refused(f"cannot read the workspace ({error})") from None
        # Once more right before the renames: the walk above can take a while. ~/personal too, since
        # an empty target skeleton is pruned and replaced.
        running = processes_in([work, old_work, personal])
        if running:
            raise Refused("hermes processes have their working directory in a tree to move: "
                          + "; ".join(running) + ". Stop them (README, deploy window), then run again")

        if move_personal:
            if personal.exists():
                prune_empty(personal)
            for name in set(companies) | {".tasks"}:
                skeleton = work / name
                if skeleton.is_dir() and not has_content(skeleton):
                    prune_empty(skeleton)
            work.rename(personal)
            log(f"moved {work} -> {personal}")
        if move_work:
            if work.exists():
                prune_empty(work)
            old_work.rename(work)
            log(f"moved {old_work} -> {work}")
        failed = []
        # The moves are mapped in order: a file first moved with ~/work, never with ~/work-devzero.
        for path, text in rewrites.items():
            target = relocate(path, moves)
            try:
                write_text(target, text)
                log(f"updated {target}")
            except OSError as error:
                failed.append(f"{target} ({error})")
        for item in failed:
            log(f"warning: could not update {item}; run `git worktree repair <worktree path>` in its repo")
        prune_stale(home)
        if old_work.exists() or old_work.is_symlink():
            # A file arrived in ~/work-devzero during a personal-only move: run again once it is sorted.
            log(f"warning: {old_work} still holds files; not stamping, so the next run looks again")
        else:
            stamp(home, "moved")
        return 0


def main(argv):
    if len(argv) < 2 or not Path(argv[1]).is_absolute():
        log("usage: _hermes-workspace-migrate.py HOME COMPANY...")
        return 1
    home, companies = Path(argv[1]), argv[2:]
    try:
        return migrate(home, companies)
    except Refused as reason:
        log(f"REFUSED, nothing changed: {reason}. The task commands refuse until the move is done; "
            "see README, Hermes workspaces on stygies.")
        return REFUSED


if __name__ == "__main__":
    os.umask(0o077)
    sys.exit(main(sys.argv))
