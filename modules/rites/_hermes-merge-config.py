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


def write_config(path, config):
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=path.parent, mode="w", encoding="utf-8", delete=False) as stream:
        tmp = Path(stream.name)
        try:
            yaml.dump(config, stream)
            stream.close()
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)


def apply(home, overlay):
    tombstones = home / "profiles/.deleted"
    provisioned = home / "profiles/.nixos-managed"
    provisioned.mkdir(parents=True, exist_ok=True)
    for source in sorted(overlay.glob("profiles/*/config.yaml")):
        name = source.parent.name
        update_config(home / source.relative_to(overlay), read_config(source))
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
