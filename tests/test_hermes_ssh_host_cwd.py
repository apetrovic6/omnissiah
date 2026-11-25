"""The ssh host-path guard patched into Hermes (modules/rites/_hermes-ssh-host-cwd.py), without Hermes."""

import importlib.util
import os
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

HELPER = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-ssh-host-cwd.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("nixos_ssh_host_cwd", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HostOnlyFallback(unittest.TestCase):
    def setUp(self):
        self.guard = load_helper()
        self.scoped = "~/work"
        runtime_cwd = types.ModuleType("agent.runtime_cwd")
        runtime_cwd.scope_terminal_cwd = lambda: self.scoped() if callable(self.scoped) else self.scoped
        agent = types.ModuleType("agent")
        agent.runtime_cwd = runtime_cwd
        self.enterContext(mock.patch.dict(sys.modules, {"agent": agent, "agent.runtime_cwd": runtime_cwd}))
        self.enterContext(mock.patch.dict(os.environ, {self.guard.ENV: "/var/lib/hermes"}))

    def test_host_paths_fall_back_to_scoped_cwd(self):
        for cwd in ("/var/lib/hermes", "/var/lib/hermes/projects/rat",
                    "/var/lib/hermes/.hermes/profiles/coder/projects-rust-app-template", "/var/lib/hermes/a/../b"):
            with self.subTest(cwd=cwd), self.assertLogs("tools.terminal_tool", "WARNING") as logs:
                self.assertEqual(self.guard.host_only_fallback(cwd), "~/work")
            self.assertIn(cwd, logs.output[0])

    def test_remote_paths_pass_through(self):
        for cwd in ("/home/hermes/work/rat", "/var/lib/hermes2/x", "/var/lib", "/tmp/x", "~/work", "~", "relative",
                    "/var/lib/hermes/../other"):
            with self.subTest(cwd=cwd):
                self.assertIsNone(self.guard.host_only_fallback(cwd))

    def test_unset_or_unusable_prefixes_disable_the_guard(self):
        for value in ("", "relative/path", "/", " : "):
            with self.subTest(value=value), mock.patch.dict(os.environ, {self.guard.ENV: value}):
                self.assertIsNone(self.guard.host_only_fallback("/var/lib/hermes/x"))
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(self.guard.host_only_fallback("/var/lib/hermes/x"))

    def test_several_prefixes(self):
        with mock.patch.dict(os.environ, {self.guard.ENV: "/srv/a/:/var/lib/hermes"}), \
                self.assertLogs("tools.terminal_tool", "WARNING"):
            self.assertEqual(self.guard.host_only_fallback("/srv/a/b"), "~/work")
            self.assertEqual(self.guard.host_only_fallback("/var/lib/hermes/c"), "~/work")

    def test_fallback_when_scoped_cwd_is_unusable(self):
        for scoped, expected in (("", "~"), (".", "~"), ("/var/lib/hermes/w", "~"), ("/home/hermes/work-devzero",
                                                                                      "/home/hermes/work-devzero"),
                                 ("~/work-devzero", "~/work-devzero")):
            self.scoped = scoped
            with self.subTest(scoped=scoped), self.assertLogs("tools.terminal_tool", "WARNING"):
                self.assertEqual(self.guard.host_only_fallback(f"/var/lib/hermes/{scoped or 'x'}-p"), expected)

    def test_scope_error_falls_back_to_home(self):
        def refuse():
            raise RuntimeError("terminal policy unavailable")
        self.scoped = refuse
        with self.assertLogs("tools.terminal_tool", "WARNING"):
            self.assertEqual(self.guard.host_only_fallback("/var/lib/hermes/x"), "~")

    def test_warns_once_per_path(self):
        with self.assertLogs("tools.terminal_tool", "WARNING") as logs:
            for _ in range(3):
                self.guard.host_only_fallback("/var/lib/hermes/x")
            self.guard.host_only_fallback("/var/lib/hermes/y")
        self.assertEqual(len(logs.output), 2)


if __name__ == "__main__":
    unittest.main()
