"""NixOS (omnissiah): keep Hermes-host paths out of an ssh terminal's working directory.

Copied into the Hermes package as ``tools/nixos_ssh_host_cwd.py`` and called from
``coerce_ssh_remote_cwd`` (modules/rites/hermes.nix, postPatch), the function every ssh
terminal and file-tool cwd passes through. Hermes normalises project paths on the gateway
host (``projects_db._normalize_path``: ``~/work/x`` becomes ``/var/lib/hermes/work/x``), and
the app hands a picked project's path to the remote verbatim, so every command's
``builtin cd -- <cwd> || exit 126`` failed on stygies before the command ran.

A cwd at or under one of ``HERMES_SSH_HOST_ONLY_PREFIXES`` (colon-separated, absolute; unset
means off) exists only on the gateway host. It is replaced by the active profile's configured
cwd (``terminal.cwd``, e.g. ``~/work``), or ``~`` when that is unusable too. An explicit
``workdir`` the agent passes is not redirected: running it somewhere else would be worse than
the ``cd`` error.
"""

import logging
import os
import posixpath

logger = logging.getLogger("tools.terminal_tool")

ENV = "HERMES_SSH_HOST_ONLY_PREFIXES"
_warned: set[str] = set()


def _prefixes() -> list[str]:
    # "/" would redirect every absolute path, so it is ignored.
    return [p for p in (posixpath.normpath(raw.strip()) for raw in os.environ.get(ENV, "").split(":")
                        if posixpath.isabs(raw.strip())) if p != "/"]


def _host_only(path: str, prefixes: list[str]) -> bool:
    path = posixpath.normpath(path)
    return any(path == prefix or path.startswith(prefix + "/") for prefix in prefixes)


def _configured_cwd() -> str:
    """The active profile's ``TERMINAL_CWD`` (per-turn scope under gateway multiplexing)."""
    try:
        from agent.runtime_cwd import scope_terminal_cwd

        return str(scope_terminal_cwd() or "").strip()
    except Exception:  # an unreadable profile scope: the terminal refuses the call anyway
        return ""


def host_only_fallback(cwd: str) -> str | None:
    """The remote cwd to use instead of ``cwd``, or None when ``cwd`` may reach the remote as is."""
    prefixes = _prefixes()
    if not prefixes or not posixpath.isabs(cwd) or not _host_only(cwd, prefixes):
        return None
    configured = _configured_cwd()
    if configured.startswith("~") or (posixpath.isabs(configured) and not _host_only(configured, prefixes)):
        fallback = configured
    else:
        fallback = "~"
    if cwd not in _warned:
        _warned.add(cwd)
        logger.warning("ssh working directory %s exists only on the Hermes host; using %s on the remote instead "
                       "(give app projects remote paths, e.g. /home/hermes/work/<repo>)", cwd, fallback)
    return fallback
