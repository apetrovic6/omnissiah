"""One-time move of Hermes's stygies workspaces to the 2026-11 layout. Idempotent; run as hermes.

    old                                  new
    ~/work (personal repos, slot)    ->  ~/personal
    ~/work-devzero/{<company>,.tasks} -> ~/work

Usage: _hermes-workspace-migrate.py HOME COMPANY...  (COMPANY: every name in _work-projects.nix)

Runs from stygies's activation, before tmpfiles creates the new directories, but tolerates the
empty skeleton tmpfiles leaves after a refused run: a tree of empty directories is not state.
It plans both moves before doing either, and refuses (changes nothing) when the state is
ambiguous, a slot being moved has an active task, or a task command holds a slot lock.
Exit status: 0 nothing to do or migrated, 3 refused, 1 unexpected error. The caller never
fails the deploy on it.
"""

import fcntl
import os
import sys
import time
from contextlib import ExitStack
from pathlib import Path
from tempfile import NamedTemporaryFile

TAG = "hermes-workspace-migrate"
REFUSED = 3
LOCK_WAIT = 10


class Refused(Exception):
    pass


def log(message):
    print(f"{TAG}: {message}", file=sys.stderr, flush=True)


def has_content(path):
    """True when ``path`` is, or holds anywhere below it, anything but a directory (symlinks count)."""
    try:
        if path.is_symlink() or not path.is_dir():
            return path.exists() or path.is_symlink()
        with os.scandir(path) as entries:
            return any(not entry.is_dir(follow_symlinks=False) or has_content(Path(entry.path)) for entry in entries)
    except FileNotFoundError:
        return False


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
        return bool((slot / ".current-task").read_text(encoding="utf-8").strip())
    except FileNotFoundError:
        return False


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


def plan(home, companies):
    old_personal = new_work = home / "work"
    new_personal = home / "personal"
    old_work = home / "work-devzero"
    for path in (new_work, new_personal, old_work):
        if path.is_symlink():
            raise Refused(f"{path} is a symlink; resolve it by hand (README, manual fallback)")
    markers = set(companies) | {".tasks"}
    work_state = classify_work(new_work, markers)
    move_personal = work_state == "personal"
    move_work = has_content(old_work)
    if work_state == "mixed" and (move_work or not has_content(new_personal)):
        raise Refused(f"{new_work} holds both personal entries and company/.tasks entries")
    if move_personal and has_content(new_personal):
        raise Refused(f"{old_personal} still has the old personal layout but {new_personal} is not empty")
    if move_work and work_state in ("work", "mixed"):
        raise Refused(f"both {old_work} and {new_work} hold company state")
    if work_state == "mixed":
        log(f"warning: {new_work} holds personal entries next to company ones; nothing to migrate, check it by hand")
    slots = ([old_personal] if move_personal else []) + (company_slots(old_work) if move_work else [])
    return move_personal, move_work, slots


def rewrite_gitdirs(tree, moves):
    """Point absolute git paths (linked worktrees) from the moved locations at the new ones."""
    def mapped(text):
        for old, new in moves:
            for prefix in (f"gitdir: {old}/", f"{old}/"):
                if text.startswith(prefix):
                    return text.replace(f"{old}/", f"{new}/", 1)
        return None

    def rewrite(path):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            return
        new = mapped(text)
        if new is None:
            return
        with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
            stream.write(new)
        os.chmod(stream.name, path.stat().st_mode & 0o7777)
        os.replace(stream.name, path)
        log(f"updated {path}")

    def walk(directory):
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                if entry.name == ".git":
                    if entry.is_file(follow_symlinks=False):
                        rewrite(path)  # a linked worktree: "gitdir: /abs/repo/.git/worktrees/<n>"
                    elif entry.is_dir(follow_symlinks=False):
                        for gitdir in sorted(path.glob("worktrees/*/gitdir")):
                            rewrite(gitdir)  # the repo's back-pointer to the worktree's .git file
                        config = path / "config"
                        try:
                            if any(old in config.read_text(encoding="utf-8", errors="replace") for old, _ in moves):
                                log(f"warning: {config} names an old workspace path; fix it by hand")
                        except OSError:
                            pass
                elif entry.is_dir(follow_symlinks=False):
                    walk(path)

    walk(tree)


def prune_stale(home):
    """An old ~/work-devzero with nothing in it (tmpfiles' last directory) goes."""
    stale = home / "work-devzero"
    if stale.is_dir() and not stale.is_symlink() and not has_content(stale):
        prune_empty(stale)
        log(f"removed the empty {stale}")


def migrate(home, companies):
    with ExitStack() as stack:
        move_personal, move_work, slots = plan(home, companies)
        if not (move_personal or move_work):
            prune_stale(home)
            return 0
        lock_slots(stack, slots)
        busy = [str(slot) for slot in slots if active(slot)]
        if busy:
            raise Refused(f"active task in {', '.join(busy)}; finish or clear it, then deploy again")
        # Re-plan under the locks: a task command may have run between the first look and the lock.
        if plan(home, companies)[:2] != (move_personal, move_work):
            raise Refused("the workspace changed while planning; deploy again")

        moves = []
        work, personal, old_work = home / "work", home / "personal", home / "work-devzero"
        if move_personal:
            if personal.exists():
                prune_empty(personal)
            for name in set(companies) | {".tasks"}:
                skeleton = work / name
                if skeleton.is_dir() and not has_content(skeleton):
                    prune_empty(skeleton)
            work.rename(personal)
            moves.append((str(work), str(personal)))
            log(f"moved {work} -> {personal}")
        if move_work:
            if work.exists():
                prune_empty(work)
            old_work.rename(work)
            moves.append((str(old_work), str(work)))
            log(f"moved {old_work} -> {work}")
        for _, new in moves:
            rewrite_gitdirs(Path(new), moves)
        prune_stale(home)
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
