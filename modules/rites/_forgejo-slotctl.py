#!/usr/bin/env python3
"""slotctl: do one validated thing to one nix-eph slot on this host (HOM-32).

The dispatcher decides and slotctl acts. slotctl is the only code that touches a slot's systemd units, its
staged runner credentials, its disk images and its trust share. A call names a slot from the baked host
config and one fixed verb. Secrets arrive as JSON on stdin, never in argv. Each call holds the canonical
slot lock; local dispatch also supplies its already-held state lock with --hold-fd.

  observe               the VM, support units, VM again, and current run marker
  check-space           check available space on the VM image filesystem (no reservation)
  reset-failed
  stop-support UNIT...  only this slot's support units
  stage RUN             stdin {"uuid", "token", "handle"}; sets the run marker before staging
  start RUN             arms the slot host's cutoff before queuing a VM start
  stop RUN              queues a VM stop, or cleans up the cutoff if already idle
  scrub RUN|none        requires a matching marker and stopped VM; clears marker
  deliver RUN           stdin {"ncps-netrc": base64, "ci-signing-key": base64}; requires a slot that
                        delivers and an active VM with no job queued; disarms the cutoff after delivery
  withdraw RUN|none     removes delivered CI credentials, keeps the trust directory; ends trusted egress first
  egress trusted RUN    starts forgejo-ephemeral-trusted-egress@SLOT, the second SNAT source; requires a host
                        with trusted egress, a settled running VM and delivered credentials. The unit probes
                        for a duplicate address first. Ended by the VM's stop (BindsTo) or by its address going;
                        withdraw and scrub run its root cleanup unit, which must leave no rule or flow
                        (else egress-cleanup-failed, and the slot stays unusable).

Exit status and stderr carry fixed codes only, nothing derived from input:
  0  done
  1  refused: one code from CODES
  2  invalid-request: bad command line, config or input
  3  unexpected-failure
"""

import argparse
import base64
import binascii
import fcntl
import grp
import json
import os
import pwd
import re
import shlex
import stat
import subprocess
import sys
import time
from pathlib import Path

# Host paths are compiled in by replaceVars (forgejo-runner-ephemeral.nix).
CONFIG = "@config@"
SYSTEMCTL_PATH = "@systemctl@"
SYSTEMD_RUN_PATH = "@systemd_run@"
PYTHON_PATH = "@python@"
SUPPORT_UNITS = ("tap-interfaces", "macvtap-interfaces", "pci-devices", "virtiofsd", "set-booted")
RESULTS = ("success", "timeout", "exit-code", "signal", "core-dump", "resources", "start-limit-hit")
STATES_IDLE = ("inactive", "failed")
STATES_BUSY = ("active", "activating", "deactivating", "reloading", "refreshing")
IMAGES = ("nix-store-overlay.img", "var.img")
CREDENTIALS = ("runner-uuid", "runner-token", "job-handle", "forgejo-url", "runner-label")
TRUST_FILES = ("ncps-netrc", "ci-signing-key")  # Written first, in this order; then the optional sccache file.
SCCACHE_FILE = "sccache-credentials"
TRUST_NAMES = (*TRUST_FILES, SCCACHE_FILE)
TRUST_NAMES += tuple(f".{name}.tmp" for name in TRUST_NAMES)
TRUST_SHAPES = {
    "ci-signing-key": re.compile(rb"[A-Za-z0-9._-]{1,255}:[A-Za-z0-9+/]{20,400}={0,2}\n?"),
    "ncps-netrc": re.compile(rb"machine ncps\.noosphere\.uk\nlogin [!-~]{1,255}\npassword [!-~]{1,4096}\n?"),
    SCCACHE_FILE: re.compile(rb"\[default\]\naws_access_key_id = GK[0-9a-f]{24}\naws_secret_access_key = [0-9a-f]{64}\n"),
}
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
SLOT_NAME = re.compile(r"[a-z][a-z0-9-]{0,62}")
TOKEN = re.compile(r"[!-~]{1,4096}")
UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
FORGE_URLS = ("https://forge.ugalabugala.org", "https://forge.noosphere.uk")
LABEL_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
MAX_INPUT = 64 * 1024
VERBS = ("observe", "check-space", "start", "stop", "reset-failed", "stop-support", "stage", "scrub", "deliver", "withdraw", "egress")
RUN_VERBS = ("stage", "start", "stop", "scrub", "deliver", "withdraw", "egress")
EGRESS_MODES = ("trusted",)  # Untrusted is the default source; withdraw and scrub return to it.
# Exit statuses of the trusted egress unit (egressStart in forgejo-runner-ephemeral.nix).
EGRESS_EXITS = {"10": "egress-address-conflict", "11": "egress-address-missing"}
LOCK_ROOT = Path("/run/forgejo-slotctl")
LOCK_WAIT = 2.0
MAX_COMMAND = 1024
MAX_RUN = 113  # eph- + 12 hex + '-' + max 63-char slot + '-' + 32 hex
UNIT_NOT_INSTALLED = 5  # systemctl's LSB exit status for StopUnit on a missing unit.
# The trusted egress cleanup unit's TimeoutStartSec is 60 s; the remote sandbox allows 95 s.
CLEANUP_WAIT = 70
CODES = (
    "systemctl-failed",
    "watchdog-arm-failed",
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
    "slot-busy",
    "slot-lock",
    "disk-space-check",
    "disk-space-low",
    "run-mismatch",
    "run-exists",
    "run-marker",
    "remote-launch",
    "no-trusted-egress",
    "egress-not-delivered",
    "egress-address-conflict",
    "egress-address-missing",
    "egress-failed",
    "egress-cleanup-failed",
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


def run_pattern(slot):
    namespace = "ryza" if slot == "ryza-eph-1" else slot
    return re.compile(rf"eph-[0-9a-f]{{12}}-{re.escape(namespace)}-[0-9a-f]{{32}}")


def support_units(slot):
    return tuple(f"microvm-{name}@{slot}.service" for name in SUPPORT_UNITS)


class Systemctl:
    def __init__(self, slot, run, path, lock_fds, systemd_run_path, python_path, expiry_minutes):
        self.slot = slot
        self.vm = f"microvm@{slot}.service"
        self.egress = f"forgejo-ephemeral-trusted-egress@{slot}.service"
        self.egress_cleanup = f"forgejo-ephemeral-trusted-egress-cleanup@{slot}.service"
        self.support = support_units(slot)
        self.kinds = {self.vm: "vm", **dict(zip(self.support, SUPPORT_UNITS, strict=True))}
        self.run = run
        self.path, self.lock_fds = path, lock_fds
        self.systemd_run_path, self.python_path = systemd_run_path, python_path
        self.expiry_minutes = expiry_minutes

    def _system_command(self, argv, *, missing_ok=False, timeout=10):
        try:
            result = self.run(
                argv,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                # A child issuing a systemd operation must keep the lock held
                # even if slotctl dies before the reply.
                pass_fds=self.lock_fds,
                timeout=timeout,
                check=True,
            )
        except subprocess.CalledProcessError as error:
            if missing_ok and error.returncode == UNIT_NOT_INSTALLED:
                return b""
            raise SlotError("systemctl-failed") from None
        except (OSError, subprocess.SubprocessError):
            raise SlotError("systemctl-failed") from None
        return result.stdout

    def _call(self, action, *units, options=(), missing_ok=False, timeout=10):
        return self._system_command(
            (self.path, "--system", "--no-pager", *options, action, *units),
            missing_ok=missing_ok, timeout=timeout,
        )

    def state(self, unit):
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
                return active, bool(job and int(job)), result
        except (KeyError, ValueError):
            pass
        raise SlotError(f"unknown-state-{self.kinds[unit]}")

    def observe(self, unit):
        active, pending, result = self.state(unit)
        return active in STATES_IDLE and not pending, result

    def idle(self, unit):
        return self.observe(unit)[0]

    def running(self, unit):
        """Up and settled: ActiveState=active with no job queued (not starting, stopping or queued to start)."""
        active, queued, _ = self.state(unit)
        return active == "active" and not queued

    def expiry_unit(self, run_name):
        return f"forgejo-slot-expiry-{self.slot}-{run_name}"

    def arm_expiry(self, run_name):
        # Wait for PID 1 to activate the timer, not just queue its start. Its
        # service belongs to the slot host, not the dispatcher or SSH session.
        self._system_command((
            self.systemd_run_path, "--system", "--quiet", "--collect",
            f"--unit={self.expiry_unit(run_name)}",
            f"--on-active={self.expiry_minutes}min",
            "--timer-property=AccuracySec=1us", "--timer-property=RemainAfterElapse=no",
            "--service-type=exec", "--expand-environment=no",
            "--property=Restart=on-failure", "--property=RestartMode=direct",
            "--property=RestartSec=1s", "--property=StartLimitIntervalSec=0",
            "--property=RuntimeMaxSec=20s", "--property=TimeoutStopSec=2s",
            "--property=RestrictAddressFamilies=AF_UNIX", "--property=NoNewPrivileges=yes",
            "--property=ProtectSystem=strict", "--property=ProtectHome=yes", "--property=CapabilityBoundingSet=",
            "--",
            self.python_path, "-I", "-B", os.path.abspath(__file__), "--slot", self.slot, "expire", run_name,
        ))

    def disarm_expiry(self, run_name):
        unit = self.expiry_unit(run_name)
        # Stop the trigger first, then cancel any already queued/running
        # expiry job. The canonical lock still excludes the expiry handler.
        for suffix in (".timer", ".service"):
            self._call("stop", unit + suffix, options=("--quiet",), missing_ok=True)

    def expire(self):
        # Wait for completion. An unavailable manager, a failed job, or a
        # busy lock must cause PID 1 to retry, not consume the only cutoff.
        self._call("stop", self.vm)

    def start(self):
        self._call("start", self.vm, options=("--no-block", "--job-mode=fail"))

    def stop(self):
        self._call("stop", self.vm, options=("--no-block",))

    def reset_failed(self):
        self._call("reset-failed", self.vm)

    def stop_support(self, units):
        self._call("stop", *units, options=("--no-block",))

    def _egress_exit(self):
        output = self._call("show", self.egress, options=("--property=Result,ExecMainStatus,ExecMainExitTimestampMonotonic",))
        props = dict(line.split("=", 1) for line in output.decode("ascii").splitlines())
        return props["Result"], props["ExecMainStatus"], props["ExecMainExitTimestampMonotonic"]

    def start_egress(self):
        """Wait until the unit is ready; a failed start's own exit status says why.

        10 and 11 count only if this start ran ExecStart (a new main process exit) and it ended with an exit
        code. A start that never ran it (a failed dependency, a start limit, a lost reply) leaves the previous
        run's status in place, which must not be read as this run's refusal.
        """
        try:
            before = self._egress_exit()[2]
        except (SlotError, KeyError, ValueError, UnicodeError):
            raise SlotError("egress-failed") from None
        try:
            self._call("start", self.egress, options=("--job-mode=fail",))
        except SlotError:
            code = "egress-failed"
            try:
                result, status, exited = self._egress_exit()
                if result == "exit-code" and exited not in ("0", "", before):
                    code = EGRESS_EXITS.get(status, code)
            except (SlotError, KeyError, ValueError, UnicodeError):
                pass
            raise SlotError(code) from None

    def clean_egress(self):
        """The root cleanup unit stops the egress unit, removes any rule or flow it left and clears its failed
        state. It fails while anything is left, and then so does this: the slot must not boot again."""
        try:
            self._call("start", self.egress_cleanup, options=("--job-mode=fail",), timeout=CLEANUP_WAIT)
        except SlotError:
            raise SlotError("egress-cleanup-failed") from None


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
    def __init__(self, vm_dir, credentials, uid, gid, trust_dir, deliver, *, fixed_pilot=False, trusted_egress=False):
        self.vm_dir = vm_dir
        self.credentials = credentials
        self.staging = credentials.with_name(f".{credentials.name}.staging")
        self.uid, self.gid = uid, gid
        # Root-only (0700 root, files 0400 root): virtiofsd (root) serves it; QEMU's user never reads it.
        # Always cleaned (scrub, withdraw), the sccache names included even where this host
        # never delivers them, so turning delivery off never strands delivered keys. Builds
        # before HOM-32 PR 12 lack those names: drain and scrub before rolling back past it.
        self.trust_dir = trust_dir
        # Whether this slot's guest has the trust share: then stage creates it and deliver may fill it.
        self.deliver_enabled = deliver
        self.fixed_pilot = fixed_pilot
        # Whether this host has a second SNAT source for delivered runs.
        self.trusted_egress = trusted_egress

    def delivered(self):
        """Both credentials are in place as deliver leaves them: nonempty regular files."""
        try:
            fd = os.open(self.trust_dir, DIR_FLAGS)
        except OSError:
            return False
        try:
            for name in TRUST_FILES:
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
                    return False
            return True
        except OSError:
            return False
        finally:
            os.close(fd)

    def require_free_space(self, min_free_bytes):
        try:
            fd = os.open(self.vm_dir, DIR_FLAGS)
            try:
                space = os.fstatvfs(fd)
            finally:
                os.close(fd)
        except OSError:
            raise SlotError("disk-space-check") from None
        if space.f_bavail * space.f_frsize < min_free_bytes:
            raise SlotError("disk-space-low")

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
            for name in (*TRUST_FILES, SCCACHE_FILE):
                if name not in secrets:
                    continue
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

    def stage(self, runner_uuid, token, handle, url, label):
        if self.deliver_enabled:
            try:
                # Fresh and empty for every boot: virtiofsd needs it to exist when the slot starts.
                self.trust_dir.mkdir(mode=0o700)
            except OSError:
                raise SlotError("trust-dir-create-failed") from None
        try:
            self.staging.mkdir(mode=0o700)
            values = (runner_uuid, token, handle)
            if not self.fixed_pilot:
                values += (url, label)
            for name, value in zip(CREDENTIALS[:len(values)], values, strict=True):
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

    def check_space(self, min_free_bytes):
        self.files.require_free_space(min_free_bytes)

    def start(self, min_free_bytes, run_name):
        self.check_space(min_free_bytes)
        if not self.systemctl.idle(self.systemctl.vm):
            raise SlotError("vm-not-stopped")
        # Leave the timer in place even if the start reply is lost.
        try:
            self.systemctl.arm_expiry(run_name)
        except SlotError:
            # Regardless of the timer result, we have not asked PID 1 to start the VM.
            raise SlotError("watchdog-arm-failed") from None
        self.systemctl.start()

    def stop(self, run_name):
        if self.systemctl.idle(self.systemctl.vm):
            self.systemctl.disarm_expiry(run_name)
        else:
            # A queued stop is not a stopped VM. Keep the watchdog until
            # the idle stop/scrub path can safely cancel it.
            self.systemctl.stop()

    def stage(self, payload, save_run):
        if (
            not isinstance(payload, dict)
            or payload.keys() != {"uuid", "token", "handle", "url", "label"}
            or not matches(UUID, payload["uuid"])
            or not matches(TOKEN, payload["token"])
            or not handle_ok(payload["handle"])
            or payload["url"] not in FORGE_URLS
            or not matches(LABEL_NAME, payload["label"])
            or (self.files.fixed_pilot and (payload["url"], payload["label"]) != (FORGE_URLS[0], "nix-eph"))
        ):
            raise UsageError
        save_run()
        self.files.stage(payload["uuid"], payload["token"], payload["handle"], payload["url"], payload["label"])

    def scrub(self, run_name):
        # The caller checked too, but the images and credentials go only once the VM is down.
        if not self.systemctl.idle(self.systemctl.vm):
            raise SlotError("vm-not-stopped")
        if run_name is not None:
            self.systemctl.disarm_expiry(run_name)
        failure = self._clean_egress()
        self.files.scrub()
        if failure is not None:
            raise failure

    def deliver(self, payload, run_name):
        if not isinstance(payload, dict):
            raise UsageError
        names = set(TRUST_FILES)
        if payload.keys() != names and not (
            self.files.trusted_egress and payload.keys() == names | {SCCACHE_FILE}
        ):
            raise UsageError
        secrets = {}
        for name in payload:
            try:
                value = base64.b64decode(payload[name], validate=True)
            except (TypeError, ValueError, binascii.Error):
                raise UsageError from None
            if not TRUST_SHAPES[name].fullmatch(value):
                raise UsageError
            secrets[name] = value
        if not self.files.deliver_enabled:
            raise SlotError("no-trust-share")
        # Don't populate the share before trust preflight or while its stop hook is removing it.
        if not self.systemctl.running(self.systemctl.vm):
            raise SlotError("vm-not-running")
        self.files.deliver(secrets)
        self.systemctl.disarm_expiry(run_name)

    def _clean_egress(self):
        """End the trusted source if this host has one; report a failure only after the caller's cleanup."""
        if not self.files.trusted_egress:
            return None
        try:
            self.systemctl.clean_egress()
        except SlotError as error:
            return error
        return None

    def withdraw(self):
        # The source first: nothing may leave from it once the credentials are gone.
        failure = self._clean_egress()
        self.files.withdraw()
        if failure is not None:
            raise failure

    def egress_trusted(self):
        if not self.files.trusted_egress:
            raise SlotError("no-trusted-egress")
        if not self.files.deliver_enabled:
            raise SlotError("no-trust-share")
        if not self.systemctl.running(self.systemctl.vm):
            raise SlotError("vm-not-running")
        # Only a run the dispatcher has resolved as trusted and delivered to.
        if not self.files.delivered():
            raise SlotError("egress-not-delivered")
        self.systemctl.start_egress()


class Once(argparse.Action):
    """An option that may appear once: a repeat could otherwise override what came first."""

    def __call__(self, parser, namespace, values, option_string=None):
        if getattr(namespace, self.dest) is not None:
            raise UsageError
        setattr(namespace, self.dest, values)


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError


def load_config(path, slot):
    """Load this host's slot paths, QEMU identity and minimum available disk space."""
    if not isinstance(path, str) or not path.startswith("/") or "\0" in path:
        raise UsageError  # A copy that replaceVars didn't build must never run.
    try:
        with open(path, "rb") as file:
            data = json.loads(file.read(MAX_INPUT + 1))
    except (OSError, ValueError, RecursionError):
        raise UsageError from None
    entry = data.get("slots", {}).get(slot) if isinstance(data, dict) and isinstance(data.get("slots"), dict) else None
    if not isinstance(entry, dict) or entry.keys() - {"trusted_egress"} != {
        "vm_dir",
        "credential_dir",
        "trust_dir",
        "deliver",
        "fixed_pilot",
        "user",
        "group",
        "min_free_bytes",
        "expiry_minutes",
    }:
        raise UsageError
    # Present, and true, only on a host with a second source (egress.trusted in _ci-slots.nix).
    if entry.get("trusted_egress", True) is not True:
        raise UsageError
    paths = (entry["vm_dir"], entry["credential_dir"], entry["trust_dir"])
    if not all(isinstance(p, str) and p.startswith("/") and "\0" not in p for p in paths):
        raise UsageError
    if type(entry["deliver"]) is not bool or type(entry["fixed_pilot"]) is not bool:
        raise UsageError
    if not matches(SLOT_NAME, entry["user"]) or not matches(SLOT_NAME, entry["group"]):
        raise UsageError
    if any(type(entry[key]) is not int or entry[key] <= 0 for key in ("min_free_bytes", "expiry_minutes")):
        raise UsageError
    return entry


def require_private_file(fd, code):
    info = os.fstat(fd)
    if (
        not stat.S_ISREG(info.st_mode)
        or info.st_uid != os.geteuid()
        or stat.S_IMODE(info.st_mode) != 0o600
        or info.st_nlink != 1
    ):
        raise SlotError(code)


def acquire_lock(parent, slot):
    """Lock the inode created by tmpfiles. No write access to the shared lock directory."""
    fd = None
    locked = False
    try:
        info = os.fstat(parent)
        if info.st_uid != os.geteuid() or info.st_mode & 0o022:
            raise SlotError("slot-lock")
        fd = os.open(
            f"{slot}.lock",
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=parent,
        )
        require_private_file(fd, "slot-lock")
        deadline = time.monotonic() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                locked = True
                return fd
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise SlotError("slot-busy") from None
                time.sleep(min(0.05, remaining))
    except OSError:
        raise SlotError("slot-lock") from None
    finally:
        if fd is not None and not locked:
            os.close(fd)


class RunMarker:
    """Private slot state read and updated only under the canonical slot lock."""

    def __init__(self, parent, slot):
        self.parent = parent
        self.name = f"{slot}.run"
        self.pattern = run_pattern(slot)

    def read(self):
        try:
            try:
                fd = os.open(self.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.parent)
            except FileNotFoundError:
                return None
            with os.fdopen(fd, "rb") as marker:
                require_private_file(marker.fileno(), "run-marker")
                value = marker.read(MAX_RUN + 1).decode("ascii")
        except (OSError, UnicodeError):
            raise SlotError("run-marker") from None
        if not matches(self.pattern, value):
            raise SlotError("run-marker")
        return value

    def save(self, run_name):
        temporary = f".{self.name}.tmp"
        try:
            # A prior process may have died before rename. The directory is protected and locked.
            try:
                os.unlink(temporary, dir_fd=self.parent)
            except FileNotFoundError:
                pass
            fd = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=self.parent,
            )
            with os.fdopen(fd, "wb") as marker:
                marker.write(run_name.encode("ascii"))
                marker.flush()
                os.fsync(marker.fileno())
            os.rename(temporary, self.name, src_dir_fd=self.parent, dst_dir_fd=self.parent)
        except OSError:
            raise SlotError("run-marker") from None

    def clear(self):
        try:
            os.unlink(self.name, dir_fd=self.parent)
        except FileNotFoundError:
            pass
        except OSError:
            raise SlotError("run-marker") from None


def read_input(data):
    if len(data) > MAX_INPUT:
        raise UsageError
    try:
        return json.loads(data)
    except (ValueError, RecursionError):
        raise UsageError from None


def parse_command(argv, *, remote=False):
    # No abbreviated or repeated options; no way to select a config or systemctl.
    parser = Parser(prog="slotctl", add_help=False, allow_abbrev=False)
    parser.add_argument("--slot", required=True, action=Once)
    if not remote:
        parser.add_argument("--hold-fd", type=int, action=Once)
    # Expiry is only called directly by the host's transient unit, never SSH.
    parser.add_argument("verb", choices=VERBS if remote else (*VERBS, "expire"))
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args(argv)
    if not matches(SLOT_NAME, args.slot):
        raise UsageError
    values = args.arguments
    args.run_name = None
    if args.verb in RUN_VERBS or args.verb == "expire":
        if args.verb == "expire" and args.hold_fd is not None:
            raise UsageError
        if args.verb == "egress":
            # `egress trusted RUN`: the mode is spelled out, the run is checked like any other.
            if len(values) != 2 or values[0] not in EGRESS_MODES:
                raise UsageError
            values = values[1:]
        if len(values) != 1:
            raise UsageError
        if values[0] == "none" and args.verb in ("scrub", "withdraw"):
            pass
        elif matches(run_pattern(args.slot), values[0]):
            args.run_name = values[0]
        else:
            raise UsageError
    elif args.verb == "stop-support":
        allowed = support_units(args.slot)
        if not values or len(set(values)) != len(values) or any(value not in allowed for value in values):
            raise UsageError
    elif values:
        raise UsageError
    return args


def main(
    argv=None,
    stdin=None,
    stdout=None,
    stderr=None,
    run=subprocess.run,
    *,
    config=CONFIG,
    systemctl_path=SYSTEMCTL_PATH,
    systemd_run_path=SYSTEMD_RUN_PATH,
    python_path=PYTHON_PATH,
    lock_root=LOCK_ROOT,
):
    """Path overrides are only for tests."""
    stdin = sys.stdin.buffer if stdin is None else stdin
    stdout = sys.stdout.buffer if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    parent = lock_fd = marker_parent = None
    try:
        args = parse_command(argv)
        if not all(os.path.isabs(path) for path in (systemctl_path, systemd_run_path, python_path)):
            raise UsageError
        if args.hold_fd is not None:
            # Only an open descriptor the caller passed: the dispatcher's state lock.
            if args.hold_fd < 3:
                raise UsageError
            try:
                os.fstat(args.hold_fd)
            except OSError:
                raise UsageError from None
        entry = load_config(config, args.slot)
        # An incomplete local or SSH request must not hold up the watchdog.
        payload = stdin.read(MAX_INPUT + 1) if args.verb in ("stage", "deliver") else None
        try:
            parent = os.open(lock_root, DIR_FLAGS)
        except OSError:
            raise SlotError("slot-lock") from None
        lock_fd = acquire_lock(parent, args.slot)
        lock_fds = (lock_fd,) if args.hold_fd is None else (args.hold_fd, lock_fd)
        systemctl = Systemctl(args.slot, run, systemctl_path, lock_fds, systemd_run_path, python_path, entry["expiry_minutes"])
        if args.verb in RUN_VERBS or args.verb in ("observe", "expire"):
            try:
                marker_parent = os.open(Path(entry["credential_dir"]).parent, DIR_FLAGS)
                info = os.fstat(marker_parent)
            except OSError:
                raise SlotError("run-marker") from None
            if info.st_uid != os.geteuid() or info.st_mode & 0o022:
                raise SlotError("run-marker")
            marker = RunMarker(marker_parent, args.slot)
            current = marker.read()
            if args.verb == "expire":
                if current == args.run_name:
                    systemctl.expire()
                return 0  # A delayed expiry must not affect the next run.
            if args.verb == "stage" and current is not None:
                raise SlotError("run-exists")
            if args.verb in RUN_VERBS and args.verb != "stage" and current != args.run_name:
                raise SlotError("run-mismatch")
        try:
            uid, gid = pwd.getpwnam(entry["user"]).pw_uid, grp.getgrnam(entry["group"]).gr_gid
        except KeyError:
            raise SlotError("slot-user-missing") from None
        slot = Slot(
            systemctl,
            SlotFiles(
                Path(entry["vm_dir"]), Path(entry["credential_dir"]), uid, gid, Path(entry["trust_dir"]), entry["deliver"],
                fixed_pilot=entry["fixed_pilot"], trusted_egress=entry.get("trusted_egress", False),
            ),
        )
        if args.verb == "observe":
            stdout.write(json.dumps({**slot.observe(), "run": current}, separators=(",", ":")).encode())
        elif args.verb == "check-space":
            slot.check_space(entry["min_free_bytes"])
        elif args.verb == "start":
            slot.start(entry["min_free_bytes"], args.run_name)
        elif args.verb == "stop":
            slot.stop(args.run_name)
        elif args.verb == "reset-failed":
            slot.systemctl.reset_failed()
        elif args.verb == "stop-support":
            if not slot.systemctl.idle(slot.systemctl.vm):
                raise SlotError("vm-not-stopped")
            slot.systemctl.stop_support(args.arguments)
        elif args.verb == "stage":
            slot.stage(read_input(payload), lambda: marker.save(args.run_name))
        elif args.verb == "scrub":
            slot.scrub(args.run_name)
            marker.clear()
        elif args.verb == "deliver":
            slot.deliver(read_input(payload), args.run_name)
        elif args.verb == "egress":
            slot.egress_trusted()
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
    finally:
        # Close just our copy: a surviving systemctl must keep the flock held.
        if lock_fd is not None:
            os.close(lock_fd)
        if parent is not None:
            os.close(parent)
        if marker_parent is not None:
            os.close(marker_parent)


def forced_main(*, launchers, environ=None, stderr=None, execv=os.execv):
    """Validate SSH's original command and exec only the configured per-slot launcher."""
    environ = os.environ if environ is None else environ
    stderr = sys.stderr if stderr is None else stderr
    try:
        command = environ.get("SSH_ORIGINAL_COMMAND", "")
        if not command or len(command) > MAX_COMMAND or not command.isascii() or "\0" in command:
            raise UsageError
        try:
            argv = shlex.split(command)
        except ValueError:
            raise UsageError from None
        args = parse_command(argv, remote=True)
        launcher = launchers.get(args.slot)
        if launcher is None or not os.path.isabs(launcher):
            raise UsageError
    except UsageError:
        print("invalid-request", file=stderr, flush=True)
        return 2
    try:
        execv(launcher, [launcher, "--slot", args.slot, args.verb, *args.arguments])
    except OSError:
        print("remote-launch", file=stderr, flush=True)
        return 1
    return 0  # Only an injected execv returns on success.


if __name__ == "__main__":
    sys.exit(main())
