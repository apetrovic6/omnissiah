"""Apply the Nix settings without taking ownership of Hermes's other settings."""

import codecs
import fcntl
import json
import os
import re
import sys
from collections.abc import MutableMapping
from contextlib import contextmanager
from pathlib import Path
from shutil import copyfileobj
from tempfile import NamedTemporaryFile

from ruamel.yaml import YAML


yaml = YAML()
yaml.preserve_quotes = True


def read_config(path, *, missing_ok=False):
    try:
        with path.open(encoding="utf-8") as stream:
            config = yaml.load(stream)
    except FileNotFoundError:
        if missing_ok:
            return {}
        raise
    if config is None:
        return {}
    if not isinstance(config, MutableMapping):
        raise ValueError(f"{path} must contain a YAML mapping")
    return config


def merge(config, settings):
    changed = False
    for key, value in settings.items():
        current = config.get(key)
        if isinstance(current, MutableMapping) and isinstance(value, MutableMapping):
            changed = merge(current, value) or changed
        elif key not in config or current != value:
            config[key] = value
            changed = True
    return changed


def gateway_state(path, config):
    gateway = config.get("gateway", {})
    if not isinstance(gateway, MutableMapping):
        raise ValueError(f"{path}: gateway must be a mapping")
    routes = gateway.get("profile_routes")
    if routes is not None and not isinstance(routes, list):
        raise ValueError(f"{path}: gateway.profile_routes must be a list")
    return gateway, routes or []


def route_name(route):
    return str(route.get("name", "")) if isinstance(route, MutableMapping) else ""


def update_config(path, settings, *, default_profile=False):
    config = read_config(path, missing_ok=True)
    if default_profile:
        # Keep routes configured outside Nix, and drop stale Nix room routes on switch.
        gateway, routes = gateway_state(path, config)
        unmanaged = [route for route in routes if not route_name(route).startswith("nixos-matrix-")]
        desired = settings["gateway"].pop("profile_routes") + unmanaged
        if desired or "profile_routes" in gateway:
            settings["gateway"]["profile_routes"] = desired

    if merge(config, settings) or not path.exists():
        write_config(path, config)


@contextmanager
def atomic_write(path, **kwargs):
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=path.parent, delete=False, **kwargs) as stream:
        tmp = Path(stream.name)
        try:
            yield stream
            stream.close()
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)


def write_config(path, config):
    with atomic_write(path, mode="w", encoding="utf-8") as stream:
        yaml.dump(config, stream)


CLAUDE_TOKEN_ASSIGNMENT = re.compile(rb"^[ \t]*(?:export[ \t]+)?CLAUDE_CODE_OAUTH_TOKEN[ \t]*=")
# Anthropic pool sources in the root auth.json that a work profile may inherit
# without borrowing a personal login. Hermes' read_credential_pool gives a named
# profile with no Anthropic rows of its own the root's rows, and a root manual
# row outranks the profile's env token (agent/credential_pool.py), so anything
# else would bill the personal account instead of the work token.
SAFE_ROOT_POOL_SOURCES = re.compile(r"claude_code|env:.+")


def warn(message):
    print(f"hermes: {message}", file=sys.stderr, flush=True)


def read_claude_token(path):
    """Return (state, token_or_reason), state ok/missing/invalid. Never raises, never echoes the token."""
    try:
        raw = Path(path).read_bytes()
    except FileNotFoundError:
        return "missing", f"token file {path} does not exist"
    except OSError as error:
        return "invalid", f"cannot read token file {path} ({type(error).__name__})"
    token = raw.removeprefix(codecs.BOM_UTF8).strip()
    if not token:
        return "invalid", f"token file {path} is empty"
    if not re.fullmatch(rb"[A-Za-z0-9._-]+", token):
        return "invalid", f"token file {path} does not look like a setup token"
    return "ok", token


def root_pool_problem(home):
    """Why a profile with no Anthropic rows of its own would borrow a personal credential, or None."""
    path = home / "auth.json"
    try:
        # utf-8-sig like Hermes (hermes_cli/auth.py): a BOM'd store is valid.
        store = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        return f"cannot read {path} to check its Anthropic credential pool ({type(error).__name__})"
    pool = store.get("credential_pool") if isinstance(store, dict) else None
    entries = pool.get("anthropic") if isinstance(pool, dict) else None
    if not entries:
        return None
    if not isinstance(entries, list):
        return f"{path}: credential_pool.anthropic is not a list"
    sources = sorted({str(entry.get("source")) if isinstance(entry, dict) else "?" for entry in entries})
    unsafe = [source for source in sources if not SAFE_ROOT_POOL_SOURCES.fullmatch(source)]
    if unsafe:
        # Detect only: a profile with no rows of its own borrows these, and a manual row outranks
        # its token, so the work rooms keep answering, billed to that personal credential.
        return (
            "work is BILLING A PERSONAL CREDENTIAL right now, a new token does not help: "
            f"{path} holds Anthropic sources {', '.join(unsafe)}; remove that row "
            "(`hermes -p default auth list anthropic`, then `hermes -p default auth remove anthropic <id>`) "
            "or stop the work rooms"
        )
    return None


def update_claude_token(path, token):
    """Set the key in a profile .env, or drop it when token is None. Raises OSError/ValueError."""
    path.parent.mkdir(parents=True, exist_ok=True)
    # Share Hermes's writer lock so a dashboard/CLI save cannot lose this update.
    with path.with_name(".env.lock").open("ab") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if path.is_symlink():
            raise ValueError(f"refusing a symlink for the Hermes profile environment: {path}")
        try:
            original = path.read_bytes()
        except FileNotFoundError:
            if token is None:
                return
            original = b""

        # A BOM makes Hermes's unlocked .env sanitizer rewrite the file on the next
        # standalone start (hermes_cli/env_loader.py), which can drop this update.
        body = original.removeprefix(codecs.BOM_UTF8)
        assignment = b"" if token is None else b"CLAUDE_CODE_OAUTH_TOKEN=" + token + b"\n"
        lines = []
        replaced = False
        for line in body.splitlines(keepends=True):
            if CLAUDE_TOKEN_ASSIGNMENT.match(line):
                if not replaced and assignment:
                    lines.append(assignment)
                replaced = True
            else:
                lines.append(line)
        if not replaced and assignment:
            if lines and not lines[-1].endswith((b"\n", b"\r")):
                lines.append(b"\n")
            lines.append(assignment)
        updated = b"".join(lines)
        if updated != original or (path.exists() and (path.stat().st_mode & 0o777) != 0o600):
            with atomic_write(path, mode="wb") as stream:
                stream.write(updated)


def resolve_tokens(home, specs):
    """name -> (action, token, problems) for each name=path spec; action is write, remove or keep.

    A missing file is deliberate de-provisioning (var removed or never generated): drop the token
    from the profile's .env so the profile cannot keep billing a credential nobody provisions. Any
    other problem with the file (empty, malformed, unreadable) keeps the last good token: a bad
    paste during a renewal must not also take down the working one. A valid token is always
    written, even with a root pool problem: that problem is only reported, and a rotation must
    still land.
    """
    pool = root_pool_problem(home)
    resolved = {}
    for spec in specs:
        name, path = spec.split("=", 1)
        state, value = read_claude_token(path)
        problems = []
        if state == "missing":
            problems.append(f"work rooms answer with an auth error: {value}")
            resolved[name] = ("remove", None, problems)
        elif state == "invalid":
            problems.append(f"work rooms answer with an auth error: {value}")
            resolved[name] = ("keep", None, problems)
        else:
            resolved[name] = ("write", value, problems)
        if pool:
            problems.append(pool)
    return resolved


def apply_claude_token(home, name, action, token, problems):
    for problem in problems:
        # Reasons name a path or a source, never the token.
        warn(f"profile {name}: {problem}")
    if action == "keep":
        return
    path = home / "profiles" / name / ".env"
    try:
        update_claude_token(path, token)
    except (OSError, ValueError) as error:
        warn(f"profile {name}: cannot update {path}: {error}")


def dotenv_problem(home, name, token):
    """Why work's .env does not carry exactly this token, or None. Prints neither value."""
    path = home / "profiles" / name / ".env"
    if path.is_symlink() or not path.is_file():
        return f"work rooms answer with an auth error: {path} is not a regular file, so it cannot hold the token"
    try:
        lines = path.read_bytes().removeprefix(codecs.BOM_UTF8).splitlines()
    except OSError as error:
        return f"work rooms answer with an auth error: cannot read {path} ({type(error).__name__})"
    values = [
        line.split(b"=", 1)[1].strip()
        for line in lines
        if CLAUDE_TOKEN_ASSIGNMENT.match(line)
    ]
    if values != [token]:
        return (
            f"work rooms answer with an auth error: {path} does not hold the provisioned token "
            "(the write failed; the apply warning is in the hermes-gateway journal)"
        )
    return None


def check(home, overlay, *claude_token_files):
    """Exit non-zero for any token problem apply tolerates (the hermes-work-token unit)."""
    problems = []
    for name, (action, token, found) in resolve_tokens(home, claude_token_files).items():
        problems += found
        if action == "write":
            problem = dotenv_problem(home, name, token)
            if problem:
                problems.append(problem)
    for problem in problems:
        warn(f"token problem: {problem}")
    if problems:
        warn("see README: Hermes work profile (renewal and root credential pool)")
        sys.exit(1)


def apply(home, overlay, *claude_token_files):
    # Never fail for a token: the gateway also serves default and coder. Without a usable
    # token work keeps its config (auth.adopt_external_logins: false) and its routes, so
    # its rooms error instead of falling back to default, which Hermes does for a room
    # without a route (gateway/run.py).
    claude_tokens = resolve_tokens(home, claude_token_files)
    tombstones = home / "profiles/.deleted"
    provisioned = home / "profiles/.nixos-managed"
    provisioned.mkdir(parents=True, exist_ok=True)
    for source in sorted(overlay.glob("profiles/*/config.yaml")):
        name = source.parent.name
        update_config(home / source.relative_to(overlay), read_config(source))
        # Publish the opt-out in config before the dotenv, itself a profile identity marker.
        if name in claude_tokens:
            apply_claude_token(home, name, *claude_tokens[name])
        soul = source.with_name("SOUL.md")
        if soul.is_file():
            # Fail closed rather than start the gateway without the managed prompt.
            with soul.open("rb") as src, atomic_write(home / soul.relative_to(overlay), mode="wb") as dst:
                copyfileobj(src, dst)
        (provisioned / name).touch(exist_ok=True)
        marker = tombstones / name
        try:
            if marker.read_bytes() == DISABLED_BY_NIX:
                marker.unlink()
        except FileNotFoundError:
            pass
    update_config(home / "config.yaml", read_config(overlay / "config.yaml"), default_profile=True)


DISABLED_BY_NIX = b"disabled by NixOS\n"


def retire(home, overlay, *disabled_profiles):
    provisioned = home / "profiles/.nixos-managed"
    retired = [name for name in disabled_profiles if (provisioned / name).is_file()]
    if not retired:
        return

    # Hermes uses these marks for both profile selection and gateway discovery.
    # Do not hide a profile that Nix never provisioned or overwrite a Hermes tombstone.
    tombstones = home / "profiles/.deleted"
    tombstones.mkdir(parents=True, exist_ok=True)
    for name in retired:
        try:
            with (tombstones / name).open("xb") as marker:
                marker.write(DISABLED_BY_NIX)
        except FileExistsError:
            pass

    path = home / "config.yaml"
    config = read_config(path, missing_ok=True)
    gateway, routes = gateway_state(path, config)
    # Managed routes are named nixos-matrix-<profile>-<room>; match the profile
    # field, so a profile's routes go however many rooms it had.
    remaining = [
        route
        for route in routes
        if not (route_name(route).startswith("nixos-matrix-") and route.get("profile") in retired)
    ]
    changed = remaining != routes
    if changed:
        if remaining:
            gateway["profile_routes"] = remaining
        else:
            del gateway["profile_routes"]
    if not read_config(overlay / "config.yaml") and "multiplex_profiles" in gateway:
        # With no managed profiles, leave mode selection to Hermes's single-profile guard.
        del gateway["multiplex_profiles"]
        changed = True
    if changed:
        if not gateway:
            del config["gateway"]
        write_config(path, config)
    for name in retired:
        (provisioned / name).unlink()


if __name__ == "__main__":
    action, home, overlay, *profiles = sys.argv[1:]
    os.umask(0o077)
    {"apply": apply, "retire": retire, "check": check}[action](Path(home), Path(overlay), *profiles)
