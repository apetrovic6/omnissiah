"""Apply the Nix settings without taking ownership of Hermes's other settings."""

import codecs
import fcntl
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


def read_claude_token(path):
    try:
        token = Path(path).read_bytes().rstrip(b"\r\n")
    except OSError:
        raise SystemExit(f"Cannot read Hermes profile token file: {path}") from None
    if not re.fullmatch(rb"[A-Za-z0-9._-]+", token):
        raise SystemExit(f"Invalid token in Hermes profile token file: {path}")
    return token


def update_claude_token(path, token):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Share Hermes's writer lock so a dashboard/CLI save cannot lose this update.
    with path.with_name(".env.lock").open("ab") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if path.is_symlink():
            raise SystemExit(f"Refusing a symlink for the Hermes profile environment: {path}")
        try:
            original = path.read_bytes()
        except FileNotFoundError:
            original = b""

        bom = codecs.BOM_UTF8 if original.startswith(codecs.BOM_UTF8) else b""
        assignment = b"CLAUDE_CODE_OAUTH_TOKEN=" + token + b"\n"
        lines = []
        replaced = False
        for line in original[len(bom):].splitlines(keepends=True):
            if CLAUDE_TOKEN_ASSIGNMENT.match(line):
                if not replaced:
                    lines.append(assignment)
                    replaced = True
            else:
                lines.append(line)
        if not replaced:
            if lines and not lines[-1].endswith((b"\n", b"\r")):
                lines.append(b"\n")
            lines.append(assignment)
        updated = bom + b"".join(lines)
        if updated != original or (path.stat().st_mode & 0o777) != 0o600:
            with atomic_write(path, mode="wb") as stream:
                stream.write(updated)


def apply(home, overlay, *claude_token_files):
    claude_tokens = {
        name: read_claude_token(path)
        for name, path in (spec.split("=", 1) for spec in claude_token_files)
    }
    tombstones = home / "profiles/.deleted"
    provisioned = home / "profiles/.nixos-managed"
    provisioned.mkdir(parents=True, exist_ok=True)
    for source in sorted(overlay.glob("profiles/*/config.yaml")):
        name = source.parent.name
        update_config(home / source.relative_to(overlay), read_config(source))
        # Publish the opt-out in config before the dotenv, itself a profile identity marker.
        if name in claude_tokens:
            update_claude_token(home / "profiles" / name / ".env", claude_tokens[name])
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
    {"apply": apply, "retire": retire}[action](Path(home), Path(overlay), *profiles)
