#!/usr/bin/env python3
"""slotctl: do one validated thing to one nix-eph slot on this host (HOM-32).

The dispatcher decides and slotctl acts. slotctl is the only code that touches a slot's systemd units, its
staged runner credentials, its disk images and its trust share. A call names a slot from the host's config
(--config, generated from modules/rites/_ci-slots.nix) and one fixed verb. Secrets arrive as JSON on stdin,
never in argv. Output is fixed-shape JSON (observe) or nothing, and every diagnostic is a fixed string.

  observe               the VM, each support unit, then the VM again, in that order
  start, stop, reset-failed
  stop-support UNIT...  only this slot's support units
  stage                 stdin {"uuid", "token", "handle"}: the slot's one-job runner credentials
  scrub                 refused unless the VM is stopped
  deliver               stdin {"ncps-netrc": base64, "ci-signing-key": base64}; refused unless the VM runs
  withdraw              remove delivered CI credentials, keep the trust directory

Exit status: 0 done; 1 refused, with one diagnostic line on stderr that is safe to log; 2 bad command
line, config or input; 3 unexpected failure (a generic line, never a traceback).
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

SUPPORT_UNITS = ("tap-interfaces", "macvtap-interfaces", "pci-devices", "virtiofsd", "set-booted")
RESULTS = ("success", "timeout", "exit-code", "signal", "core-dump", "resources", "start-limit-hit")
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


class SlotError(Exception):
    """A safe diagnostic for a slot that cannot be used or reused yet."""


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
            raise SlotError(f"systemctl {action} failed or timed out for {self.slot}; reconciling unit state") from None
        return result.stdout

    def observe(self, unit):
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
            if active in ("inactive", "failed"):
                return (not job or int(job) == 0), result
            if active in ("active", "activating", "deactivating", "reloading", "refreshing"):
                return False, result
        except (KeyError, ValueError):
            pass
        raise SlotError(f"unknown systemd state for {unit}; refusing slot reuse")

    def idle(self, unit):
        return self.observe(unit)[0]

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
    def __init__(self, vm_dir, credentials, uid, gid, trust_dir=None):
        self.vm_dir = vm_dir
        self.credentials = credentials
        self.staging = credentials.with_name(f".{credentials.name}.staging")
        self.uid, self.gid = uid, gid
        # Root-only (0700 root, files 0400 root): virtiofsd (root) serves it; QEMU's user never reads it.
        self.trust_dir = trust_dir

    def scrub(self):
        failed = False
        trust = () if self.trust_dir is None else ((self.trust_dir, TRUST_NAMES, True),)
        for directory, names, remove in (
            (self.vm_dir, IMAGES, False),
            (self.credentials, CREDENTIALS, True),
            (self.staging, CREDENTIALS, True),
            *trust,
        ):
            try:
                unlink_files(directory, names, remove_dir=remove)
            except OSError:
                failed = True
        if failed:
            raise SlotError("cannot scrub exact slot images or credentials; check slot paths for unexpected files")

    def withdraw(self):
        """Remove delivered credentials, keeping the directory a running slot may still be serving."""
        if self.trust_dir is not None:
            try:
                unlink_files(self.trust_dir, TRUST_NAMES)
            except OSError:
                raise SlotError("cannot remove delivered CI credentials; check the trust directory") from None

    def deliver(self, secrets):
        """Atomically place each credential (0400, owned by slotctl: root) in the existing trust dir."""
        try:
            fd = os.open(self.trust_dir, DIR_FLAGS)
        except OSError:
            raise SlotError("trust directory is missing; refusing to deliver CI credentials") from None
        try:
            info = os.fstat(fd)
            if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise SlotError("trust directory has unexpected ownership or mode; refusing to deliver")
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
            raise SlotError("cannot deliver CI credentials; check the trust directory") from None
        finally:
            os.close(fd)

    def stage(self, runner_uuid, token, handle):
        if self.trust_dir is not None:
            try:
                # Fresh and empty for every boot: virtiofsd needs it to exist when the slot starts.
                self.trust_dir.mkdir(mode=0o700)
            except OSError:
                raise SlotError("cannot create the empty trust directory; check the credential parent") from None
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
            raise SlotError("cannot stage runner credentials; check ownership and permissions of the credential parent") from None


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
            raise SlotError("VM state changed during reconciliation; waiting before slot cleanup")
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
        if self.files.trust_dir is None:
            raise SlotError("this slot has no trust share; refusing to deliver CI credentials")
        # Only into a running slot: never into a directory a stopped slot's scrub is removing.
        if self.systemctl.idle(self.systemctl.vm):
            raise SlotError("slot is not running; not delivering CI credentials")
        self.files.deliver(secrets)

    def withdraw(self):
        self.files.withdraw()


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError


def load_config(path, slot):
    """This host's entry for the slot: absolute directories, the trust share (or null) and QEMU's user."""
    try:
        with open(path, "rb") as file:
            data = json.loads(file.read(MAX_INPUT + 1))
    except (OSError, ValueError, RecursionError):
        raise UsageError from None
    entry = data.get("slots", {}).get(slot) if isinstance(data, dict) and isinstance(data.get("slots"), dict) else None
    if not isinstance(entry, dict) or entry.keys() != {"vm_dir", "credential_dir", "trust_dir", "user", "group"}:
        raise UsageError
    paths = [entry["vm_dir"], entry["credential_dir"]] + ([] if entry["trust_dir"] is None else [entry["trust_dir"]])
    if not all(isinstance(p, str) and p.startswith("/") and "\0" not in p for p in paths):
        raise UsageError
    if not matches(SLOT_NAME, entry["user"]) or not matches(SLOT_NAME, entry["group"]):
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


def main(argv=None, stdin=None, stdout=None, stderr=None, run=subprocess.run):
    stdin = sys.stdin.buffer if stdin is None else stdin
    stdout = sys.stdout.buffer if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    try:
        parser = Parser(prog="slotctl", add_help=False)
        parser.add_argument("--config", required=True)
        parser.add_argument("--slot", required=True)
        parser.add_argument("--hold-fd", type=int)
        parser.add_argument("verb", choices=VERBS)
        parser.add_argument("units", nargs="*")
        args = parser.parse_args(argv)
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
        entry = load_config(args.config, args.slot)
        try:
            uid, gid = pwd.getpwnam(entry["user"]).pw_uid, grp.getgrnam(entry["group"]).gr_gid
        except KeyError:
            raise SlotError("slot user or group is missing; check the slot host configuration") from None
        trust_dir = None if entry["trust_dir"] is None else Path(entry["trust_dir"])
        slot = Slot(
            Systemctl(args.slot, run, args.hold_fd),
            SlotFiles(Path(entry["vm_dir"]), Path(entry["credential_dir"]), uid, gid, trust_dir),
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
        print("slotctl: invalid command line, config or input", file=stderr, flush=True)
        return 2
    except SlotError as error:
        print(error, file=stderr, flush=True)
        return 1
    except Exception:
        print("slotctl: failed unexpectedly; check the slot host configuration", file=stderr, flush=True)
        return 3


if __name__ == "__main__":
    sys.exit(main())
