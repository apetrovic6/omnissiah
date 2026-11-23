"""Apply the Nix settings without taking ownership of Hermes's other settings."""

import os
import sys
from collections.abc import MutableMapping
from pathlib import Path
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


def update_config(path, settings, *, default_profile=False):
    config = read_config(path, missing_ok=True)
    if default_profile:
        # Keep routes configured outside Nix, and drop stale Nix room routes on switch.
        gateway = config.get("gateway", {})
        if not isinstance(gateway, MutableMapping):
            raise ValueError(f"{path}: gateway must be a mapping")
        routes = gateway.get("profile_routes")
        if routes is not None and not isinstance(routes, list):
            raise ValueError(f"{path}: gateway.profile_routes must be a list")
        unmanaged = [
            route for route in routes or []
            if not isinstance(route, MutableMapping)
            or not str(route.get("name", "")).startswith("nixos-matrix-")
        ]
        desired = settings["gateway"].pop("profile_routes") + unmanaged
        if desired or "profile_routes" in gateway:
            settings["gateway"]["profile_routes"] = desired

    if not merge(config, settings) and path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=path.parent, mode="w", encoding="utf-8", delete=False) as stream:
        tmp = Path(stream.name)
        try:
            yaml.dump(config, stream)
            stream.close()
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)


def main(home, overlay):
    os.umask(0o077)
    for source in sorted(overlay.glob("profiles/*/config.yaml")):
        update_config(home / source.relative_to(overlay), read_config(source))
    update_config(home / "config.yaml", read_config(overlay / "config.yaml"), default_profile=True)


if __name__ == "__main__":
    main(*map(Path, sys.argv[1:]))
