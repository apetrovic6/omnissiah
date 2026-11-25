"""Prompt-refresh bookkeeping in modules/rites/_hermes-merge-config.py, without Hermes or ruamel."""

import importlib.util
import io
import json
import sys
import types
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory

SCRIPT = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-merge-config.py"


class JsonYaml:
    """Stands in for ruamel's YAML: the overlays these tests write are JSON, which is YAML."""

    preserve_quotes = False

    def load(self, stream):
        text = stream.read()
        return json.loads(text) if text.strip() else None

    def dump(self, data, stream):
        json.dump(data, stream)


def load_merge():
    ruamel = types.ModuleType("ruamel")
    ruamel_yaml = types.ModuleType("ruamel.yaml")
    ruamel_yaml.YAML = JsonYaml
    ruamel.yaml = ruamel_yaml
    saved = {name: sys.modules.get(name) for name in ("ruamel", "ruamel.yaml")}
    sys.modules.update({"ruamel": ruamel, "ruamel.yaml": ruamel_yaml})
    try:
        spec = importlib.util.spec_from_file_location("hermes_merge_config", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        for name, value in saved.items():
            if value is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = value


merge = load_merge()


class PromptRefresh(unittest.TestCase):
    def setUp(self):
        root = Path(self.enterContext(TemporaryDirectory()))
        self.root = root
        self.home = root / "home"
        self.overlay = root / "overlay"
        self.home.mkdir()
        (self.overlay / "profiles").mkdir(parents=True)
        (self.overlay / "config.yaml").write_text(json.dumps({"gateway": {"multiplex_profiles": True, "profile_routes": []}}))
        self.managed = self.home / "profiles/.nixos-managed"
        self.write_profile("coder", soul="coder soul v1", settings={"terminal": {"cwd": "~/work"}})
        self.write_profile("work", soul="work soul v1", settings={"terminal": {"cwd": "~/work-devzero"}})

    def write_profile(self, name, *, soul=None, settings=None):
        directory = self.overlay / "profiles" / name
        directory.mkdir(parents=True, exist_ok=True)
        if settings is not None:
            (directory / "config.yaml").write_text(json.dumps(settings))
        if soul is not None:
            (directory / "SOUL.md").write_text(soul)

    def apply(self):
        merge.apply(self.home, self.overlay)

    def pending(self, name):
        return self.managed / f"{name}.refresh-prompts"

    def clear_pending(self):
        for name in ("coder", "work"):
            self.pending(name).unlink(missing_ok=True)

    # --- apply -----------------------------------------------------------------------------------

    def test_first_apply_marks_every_profile_once_after_writing_soul(self):
        self.apply()
        for name in ("coder", "work"):
            fingerprint = (self.managed / f"{name}.prompt-sources").read_text().strip()
            self.assertEqual(self.pending(name).read_text().strip(), fingerprint)
            self.assertEqual(len(fingerprint), 64)
            self.assertTrue((self.managed / name).is_file(), "retire marker still written")
        self.assertEqual((self.home / "profiles/coder/SOUL.md").read_text(), "coder soul v1")

    def test_unchanged_inputs_do_not_mark_again(self):
        self.apply()
        self.clear_pending()
        self.apply()
        self.apply()  # activation, then the gateway's preStart
        self.assertFalse(self.pending("coder").exists())
        self.assertFalse(self.pending("work").exists())

    def test_hermes_edits_to_live_config_do_not_mark(self):
        self.apply()
        self.clear_pending()
        live = self.home / "profiles/coder/config.yaml"
        live.write_text(json.dumps({**json.loads(live.read_text()), "model": {"default": "x"}}))
        self.apply()
        self.assertFalse(self.pending("coder").exists())

    def test_soul_change_marks_only_that_profile(self):
        self.apply()
        self.clear_pending()
        self.write_profile("coder", soul="coder soul v2")
        self.apply()
        self.assertTrue(self.pending("coder").exists())
        self.assertFalse(self.pending("work").exists())
        self.assertEqual((self.home / "profiles/coder/SOUL.md").read_text(), "coder soul v2")

    def test_settings_change_marks(self):
        self.apply()
        self.clear_pending()
        self.write_profile("work", settings={"terminal": {"cwd": "~/elsewhere"}})
        self.apply()
        self.assertTrue(self.pending("work").exists())
        self.assertFalse(self.pending("coder").exists())

    def test_profile_without_soul_is_tracked_by_settings(self):
        self.write_profile("plain", settings={"a": 1})
        self.apply()
        self.assertTrue(self.pending("plain").exists())

    def test_extra_overlay_input_marks_every_profile(self):
        self.apply()
        self.clear_pending()
        (self.overlay / merge.PROMPT_EXTRA).write_text("/nix/store/new-hermes")
        self.apply()
        self.assertTrue(self.pending("coder").exists())
        self.assertTrue(self.pending("work").exists())

    def test_stale_or_unreadable_fingerprint_re_marks(self):
        # A crash after the pending marker but before the fingerprint leaves the old fingerprint.
        for stale in (b"old\n", b"\xff\xfe"):
            self.apply()
            self.clear_pending()
            (self.managed / "coder.prompt-sources").write_bytes(stale)
            self.apply()
            self.assertTrue(self.pending("coder").exists())
            self.assertFalse(self.pending("work").exists())

    # --- refresh ---------------------------------------------------------------------------------

    def fake_hermes(self, body):
        path = self.root / "hermes"
        path.write_text(f"#!{sys.executable}\nimport json, os, sys, time\nfrom pathlib import Path\n{body}\n")
        path.chmod(0o755)
        return str(path)

    def refresh(self, hermes, *names):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            merge.refresh(self.home, self.overlay, hermes, *names)
        return stdout.getvalue(), stderr.getvalue()

    def test_refresh_runs_only_pending_profiles_and_clears_them(self):
        self.apply()
        self.pending("work").unlink()
        log = self.root / "calls"
        hermes = self.fake_hermes(
            f"Path({str(log)!r}).open('a').write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "print('starting up'); print(json.dumps({'epoch': 3, 'session_id': None, 'sessions': 2}))")
        out, err = self.refresh(hermes, "coder", "work")
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual(calls, [["-p", "coder", "sessions", "refresh-prompts", "--json"]])
        self.assertFalse(self.pending("coder").exists())
        self.assertIn("profile coder: requested a system prompt refresh (epoch 3, 2 session(s)", out)
        self.assertEqual(err, "")

    def test_failure_keeps_marker_and_reports(self):
        self.apply()
        hermes = self.fake_hermes("print('db locked', file=sys.stderr); sys.exit(3)")
        out, err = self.refresh(hermes, "coder")
        self.assertTrue(self.pending("coder").exists())
        self.assertIn("hermes: profile coder: refresh-prompts exited 3; kept pending", err)
        self.assertIn("db locked", err)

    def test_timeout_keeps_marker(self):
        self.apply()
        hermes = self.fake_hermes("time.sleep(10)")
        saved, merge.REFRESH_TIMEOUT = merge.REFRESH_TIMEOUT, 0.5
        try:
            _, err = self.refresh(hermes, "coder")
        finally:
            merge.REFRESH_TIMEOUT = saved
        self.assertTrue(self.pending("coder").exists())
        self.assertIn("timed out", err)

    def test_missing_executable_keeps_marker_and_continues(self):
        self.apply()
        _, err = self.refresh(str(self.root / "nope"), "coder", "work")
        self.assertTrue(self.pending("coder").exists())
        self.assertTrue(self.pending("work").exists())
        self.assertIn("profile coder: cannot run refresh-prompts", err)
        self.assertIn("profile work: cannot run refresh-prompts", err)

    def test_marker_raised_during_refresh_is_kept(self):
        self.apply()
        marker = self.pending("coder")
        hermes = self.fake_hermes(
            f"Path({str(marker)!r}).write_text('newer\\n')\n"
            "print(json.dumps({'epoch': 1, 'session_id': None, 'sessions': 0}))")
        self.refresh(hermes, "coder")
        self.assertEqual(marker.read_text(), "newer\n")

    def test_unparseable_output_still_counts_as_success(self):
        self.apply()
        self.refresh(self.fake_hermes("print('Requested a system prompt refresh')"), "coder")
        self.assertFalse(self.pending("coder").exists())

    def test_unexpected_error_is_reported_not_raised(self):
        self.apply()
        saved = merge.refresh_profile
        merge.refresh_profile = lambda *args: (_ for _ in ()).throw(RuntimeError("boom"))
        try:
            _, err = self.refresh("unused", "coder")
        finally:
            merge.refresh_profile = saved
        self.assertIn("profile coder: refresh-prompts failed (RuntimeError: boom)", err)


if __name__ == "__main__":
    unittest.main()
