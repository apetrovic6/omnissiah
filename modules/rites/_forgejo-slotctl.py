#!/usr/bin/env python3
"""slotctl: do one validated thing to one nix-eph slot on this host (HOM-32).

The dispatcher decides and slotctl acts. slotctl is the only code that touches a slot's systemd units, its
staged runner credentials, its disk images and its trust share. A call names a slot and one fixed verb. The
slot must be in this host's config, whose path is compiled in (CONFIG, set by replaceVars from
modules/rites/_ci-slots.nix), so a caller picks a slot and a verb, never a path. Secrets arrive as JSON on stdin,
never in argv. Output is fixed-shape JSON (observe) or nothing.

  observe               the VM, each support unit, then the VM again, in that order
  start, stop, reset-failed
  stop-support UNIT...  only this slot's support units
  stage                 stdin {"uuid", "token", "handle"}: the slot's one-job runner credentials
  scrub                 refused unless the VM is stopped; also clears the trust share
  deliver               stdin {"ncps-netrc": base64, "ci-signing-key": base64}; only into a slot that delivers,
                        and only while its VM is active with no job queued
  withdraw              remove delivered CI credentials, keep the trust directory

Exit status and stderr carry fixed codes only, nothing derived from input:
  0  done
  1  refused: one code from CODES; the dispatcher logs its own words for it
  2  invalid-request: bad command line, config or input
  3  unexpected-failure
"""

import argparse
import base64
import binascii
import grp
import json
import os
import pwd
import re
import stat
import subprocess
import sys
from pathlib import Path

# This host's slot config, compiled in by replaceVars (forgejo-runner-ephemeral.nix). Never a caller's choice.
CONFIG = "@config@"
SUPPORT_UNITS = ("tap-interfaces", "macvtap-interfaces", "pci-devices", "virtiofsd", "set-booted")
RESULTS = ("success", "timeout", "exit-code", "signal", "core-dump", "resources", "start-limit-hit")
STATES_IDLE = ("inactive", "failed")
STATES_BUSY = ("active", "activating", "deactivating", "reloading", "refreshing")
IMAGES = ("nix-store-overlay.img", "var.img")
CREDENTIALS = ("runner-uuid", "runner-token", "job-handle")
TRUST_FILES = ("ncps-netrc", "ci-signing-key")  # Write order: the guest hook needs both.
TRUST_NAMES = TRUST_FILES + tuple(f".{name}.tmp" for name in TRUST_FILES)
TRUST_SHAPES = {
    "ci-signing-key": re.compile(rb"[A-Za-z0-9._-]{1,255}:[A-Za-z0-9+/]{20,400}={0,2}\n?"),
    "ncps-netrc": re.compile(rb"machine ncps\.noosphere\.uk\nlogin [!-~]{1,255}\npassword [!-~]{1,4096}\n?"),
}
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
SLOT_NAME = re.compile(r"[a-z][a-z0-9-]{0,62}")
TOKEN = re.compile(r"[!-~]{1,4096}")
UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
MAX_INPUT = 64 * 1024
VERBS = ("observe", "start", "stop", "reset-failed", "stop-support", "stage", "scrub", "deliver", "withdraw")
CODES = (
    "systemctl-failed",
    "vm-not-stopped",
    "vm-not-running",
    "no-trust-share",
    "scrub-failed",
    "withdraw-failed",
    "trust-dir-missing",
    "trust-dir-unsafe",
    "deliver-failed",
    "trust-dir-create-failed",
    "stage-failed",
    "slot-user-missing",
    *(f"unknown-state-{kind}" for kind in ("vm", *SUPPORT_UNITS)),
)


class SlotError(Exception):
    """A refusal, reported as one fixed code from CODES."""

    def __init__(self, code):
        if code not in CODES:
            raise ValueError("unknown refusal code")
        super().__init__(code)
        self.code = code


class UsageError(Exception):
    """A malformed command line, config or input. Never echo it: input may carry secrets."""


def matches(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def handle_ok(value):
    return isinstance(value, str) and 0 < len(value) <= 1024 and value.isprintable()


class Systemctl:
    def __init__(self, slot, run=subprocess.run, lock_fd=None):
        self.slot = slot
        self.vm = f"microvm@{slot}.service"
        self.support = tuple(f"microvm-{name}@{slot}.service" for name in SUPPORT_UNITS)
        self.kinds = {self.vm: "vm", **dict(zip(self.support, SUPPORT_UNITS, strict=True))}
        self.run = run
        self.lock_fds = () if lock_fd is None else (lock_fd,)

    def _call(self, action, *units, options=()):
        try:
            result = self.run(
                ("systemctl", "--system", "--no-pager", *options, action, *units),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                # If the dispatcher dies while systemctl is still alive, its copy keeps the
                # dispatcher's lock held until the next dispatcher can safely reconcile.
                pass_fds=self.lock_fds,
                timeout=10,
                check=True,
            )
        except (OSError, subprocess.SubprocessError):
            raise SlotError("systemctl-failed") from None
        return result.stdout

    def state(self, unit):
        """(ActiveState, a job is queued, Result) of one of this slot's units."""
        # One GetAll via systemctl show: checking ActiveState and list-jobs separately
        # permits an already-queued start to run between the two queries.
        output = self._call("show", unit, options=("--all", "--property=LoadState,ActiveState,Job,Result"))
        try:
            props = dict(line.split("=", 1) for line in output.decode("ascii").splitlines())
            active, job, result = props["ActiveState"], props["Job"], props["Result"]
            if props["LoadState"] != "loaded" or (job and not re.fullmatch(r"[0-9]{1,10}", job)):
                raise ValueError
            if result not in RESULTS:
                result = "other result"
            if active in STATES_IDLE or active in STATES_BUSY:
                return active, bool(job) and int(job) != 0, result
        except (KeyError, ValueError):
            pass
        raise SlotError(f"unknown-state-{self.kinds[unit]}")

    def observe(self, unit):
        """(idle, Result): idle is stopped (inactive or failed) with no job queued."""
        active, queued, result = self.state(unit)
        return active in STATES_IDLE and not queued, result

    def idle(self, unit):
        return self.observe(unit)[0]

    def running(self, unit):
        """Up and settled: ActiveState=active with no job queued (not starting, stopping or queued to start)."""
        active, queued, _ = self.state(unit)
        return active == "active" and not queued

    def start(self):
        self._call("start", self.vm, options=("--no-block", "--job-mode=fail"))

    def stop(self):
        self._call("stop", self.vm, options=("--no-block",))

    def reset_failed(self):
        self._call("reset-failed", self.vm)

    def stop_support(self, units):
        self._call("stop", *units, options=("--no-block",))


def unlink_files(directory, names, *, remove_dir=False):
    try:
        fd = os.open(directory, DIR_FLAGS)
    except FileNotFoundError:
        return
    failure = None
    try:
        for name in names:
            try:
                os.unlink(name, dir_fd=fd)
            except FileNotFoundError:
                pass
            except OSError as error:
                failure = error
    finally:
        os.close(fd)
    if failure is not None:
        raise failure
    if remove_dir:
        directory.rmdir()


class SlotFiles:
    def __init__(self, vm_dir, credentials, uid, gid, trust_dir, deliver):
        self.vm_dir = vm_dir
        self.credentials = credentials
        self.staging = credentials.with_name(f".{credentials.name}.staging")
        self.uid, self.gid = uid, gid
        # Root-only (0700 root, files 0400 root): virtiofsd (root) serves it; QEMU's user never reads it.
        # Always cleaned (scrub, withdraw), so turning delivery off never strands delivered keys.
        self.trust_dir = trust_dir
        # Whether this slot's guest has the trust share: then stage creates it and deliver may fill it.
        self.deliver_enabled = deliver

    def scrub(self):
        failed = False
        for directory, names, remove in (
            (self.vm_dir, IMAGES, False),
            (self.credentials, CREDENTIALS, True),
            (self.staging, CREDENTIALS, True),
            (self.trust_dir, TRUST_NAMES, True),
        ):
            try:
                unlink_files(directory, names, remove_dir=remove)
            except OSError:
                failed = True
        if failed:
            raise SlotError("scrub-failed")

    def withdraw(self):
        """Remove delivered credentials, keeping the directory a running slot may still be serving."""
        try:
            unlink_files(self.trust_dir, TRUST_NAMES)
        except OSError:
            raise SlotError("withdraw-failed") from None

    def deliver(self, secrets):
        """Atomically place each credential (0400, owned by slotctl: root) in the existing trust dir."""
        try:
            fd = os.open(self.trust_dir, DIR_FLAGS)
        except OSError:
            raise SlotError("trust-dir-missing") from None
        try:
            info = os.fstat(fd)
            if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise SlotError("trust-dir-unsafe")
            for name in TRUST_FILES:
                temporary = f".{name}.tmp"
                try:
                    os.unlink(temporary, dir_fd=fd)
                except FileNotFoundError:
                    pass
                out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o400, dir_fd=fd)
                with os.fdopen(out, "wb") as file:
                    file.write(secrets[name])
                    file.flush()
                    os.fsync(file.fileno())
                os.rename(temporary, name, src_dir_fd=fd, dst_dir_fd=fd)
            os.fsync(fd)
        except OSError:
            raise SlotError("deliver-failed") from None
        finally:
            os.close(fd)

    def stage(self, runner_uuid, token, handle):
        if self.deliver_enabled:
            try:
                # Fresh and empty for every boot: virtiofsd needs it to exist when the slot starts.
                self.trust_dir.mkdir(mode=0o700)
            except OSError:
                raise SlotError("trust-dir-create-failed") from None
        try:
            self.staging.mkdir(mode=0o700)
            for name, value in zip(CREDENTIALS, (runner_uuid, token, handle), strict=True):
                fd = os.open(self.staging / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
                with os.fdopen(fd, "wb") as file:
                    os.fchown(file.fileno(), self.uid, self.gid)
                    file.write(value.encode())
            os.chown(self.staging, self.uid, self.gid)
            self.staging.rename(self.credentials)
        except OSError:
            raise SlotError("stage-failed") from None


class Slot:
    """The verbs. Each checks its own input; nothing here trusts the caller."""

    def __init__(self, systemctl, files):
        self.systemctl, self.files = systemctl, files

    def observe(self):
        vm = self.systemctl.observe(self.systemctl.vm)
        support = [[unit, self.systemctl.idle(unit)] for unit in self.systemctl.support]
        # Again after the support units: a start queued meanwhile must show before any cleanup.
        again = self.systemctl.observe(self.systemctl.vm)
        return {"vm": list(vm), "support": support, "again": list(again)}

    def stop_support(self, units):
        if not units or len(set(units)) != len(units) or any(unit not in self.systemctl.support for unit in units):
            raise UsageError
        self.systemctl.stop_support(units)

    def stage(self, payload):
        if (
            not isinstance(payload, dict)
            or payload.keys() != {"uuid", "token", "handle"}
            or not matches(UUID, payload["uuid"])
            or not matches(TOKEN, payload["token"])
            or not handle_ok(payload["handle"])
        ):
            raise UsageError
        self.files.stage(payload["uuid"], payload["token"], payload["handle"])

    def scrub(self):
        # The caller checked too, but the images and credentials go only once the VM is down.
        if not self.systemctl.idle(self.systemctl.vm):
            raise SlotError("vm-not-stopped")
        self.files.scrub()

    def deliver(self, payload):
        if not isinstance(payload, dict) or payload.keys() != set(TRUST_FILES):
            raise UsageError
        secrets = {}
        for name in TRUST_FILES:
            try:
                value = base64.b64decode(payload[name], validate=True)
            except (TypeError, ValueError, binascii.Error):
                raise UsageError from None
            if not TRUST_SHAPES[name].fullmatch(value):
                raise UsageError
            secrets[name] = value
        if not self.files.deliver_enabled:
            raise SlotError("no-trust-share")
        # Only into a slot that is up: never before its trust preflight (which needs the share empty) and
        # never into one stopping, whose stop hook and the next scrub are removing the share.
        if not self.systemctl.running(self.systemctl.vm):
            raise SlotError("vm-not-running")
        self.files.deliver(secrets)

    def withdraw(self):
        self.files.withdraw()


class Once(argparse.Action):
    """An option that may appear once: a repeat could otherwise override what came first."""

    def __call__(self, parser, namespace, values, option_string=None):
        if getattr(namespace, self.dest) is not None:
            raise UsageError
        setattr(namespace, self.dest, values)


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError


def parser():
    # No abbreviations (`--sl`), no help, no config option: only these two options and the verb.
    result = Parser(prog="slotctl", add_help=False, allow_abbrev=False)
    result.add_argument("--slot", action=Once, required=True)
    result.add_argument("--hold-fd", action=Once, type=int)
    result.add_argument("verb", choices=VERBS)
    result.add_argument("units", nargs="*")
    return result


def load_config(path, slot):
    """This host's entry for the slot: absolute directories, whether it delivers, and QEMU's user."""
    if not isinstance(path, str) or not path.startswith("/"):
        raise UsageError  # An unsubstituted placeholder (a copy the module did not build) must never run.
    try:
        with open(path, "rb") as file:
            data = json.loads(file.read(MAX_INPUT + 1))
    except (OSError, ValueError, RecursionError):
        raise UsageError from None
    entry = data.get("slots", {}).get(slot) if isinstance(data, dict) and isinstance(data.get("slots"), dict) else None
    if not isinstance(entry, dict) or entry.keys() != {"vm_dir", "credential_dir", "trust_dir", "deliver", "user", "group"}:
        raise UsageError
    if not all(isinstance(p, str) and p.startswith("/") and "\0" not in p for p in (entry["vm_dir"], entry["credential_dir"], entry["trust_dir"])):
        raise UsageError
    if type(entry["deliver"]) is not bool or not matches(SLOT_NAME, entry["user"]) or not matches(SLOT_NAME, entry["group"]):
        raise UsageError
    return entry


def read_input(stdin):
    data = stdin.read(MAX_INPUT + 1)
    if len(data) > MAX_INPUT:
        raise UsageError
    try:
        return json.loads(data)
    except (ValueError, RecursionError):
        raise UsageError from None


def main(argv=None, stdin=None, stdout=None, stderr=None, run=subprocess.run, config=None):
    """`config` is for the tests only; the command line can never set it."""
    stdin = sys.stdin.buffer if stdin is None else stdin
    stdout = sys.stdout.buffer if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    try:
        args = parser().parse_args(sys.argv[1:] if argv is None else argv)
        if not matches(SLOT_NAME, args.slot) or (args.units and args.verb != "stop-support"):
            raise UsageError
        if args.hold_fd is not None:
            # Only an open descriptor the caller passed: the dispatcher's state lock.
            if args.hold_fd < 3:
                raise UsageError
            try:
                os.fstat(args.hold_fd)
            except OSError:
                raise UsageError from None
        entry = load_config(CONFIG if config is None else config, args.slot)
        try:
            uid, gid = pwd.getpwnam(entry["user"]).pw_uid, grp.getgrnam(entry["group"]).gr_gid
        except KeyError:
            raise SlotError("slot-user-missing") from None
        slot = Slot(
            Systemctl(args.slot, run, args.hold_fd),
            SlotFiles(
                Path(entry["vm_dir"]), Path(entry["credential_dir"]), uid, gid, Path(entry["trust_dir"]), entry["deliver"]
            ),
        )
        if args.verb == "observe":
            stdout.write(json.dumps(slot.observe(), separators=(",", ":")).encode())
        elif args.verb == "start":
            slot.systemctl.start()
        elif args.verb == "stop":
            slot.systemctl.stop()
        elif args.verb == "reset-failed":
            slot.systemctl.reset_failed()
        elif args.verb == "stop-support":
            slot.stop_support(args.units)
        elif args.verb == "stage":
            slot.stage(read_input(stdin))
        elif args.verb == "scrub":
            slot.scrub()
        elif args.verb == "deliver":
            slot.deliver(read_input(stdin))
        else:
            slot.withdraw()
        stdout.flush()
        return 0
    except UsageError:
        print("invalid-request", file=stderr, flush=True)
        return 2
    except SlotError as error:
        print(error.code, file=stderr, flush=True)
        return 1
    except Exception:
        print("unexpected-failure", file=stderr, flush=True)
        return 3


if __name__ == "__main__":
    sys.exit(main())
