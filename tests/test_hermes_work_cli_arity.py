"""Check the work wrapper's flag allowlist against the real gh and glab binaries.

The wrapper must parse argv exactly as pflag does, so every allowed flag must
exist and take a value exactly when the wrapper thinks it does. A bool flag
followed by --help prints help; a value-taking one consumes --help as its value.

Needs the binaries stygies uses; skipped unless given, e.g.:

  HERMES_TEST_GH=$(nix eval --raw .#nixosConfigurations.stygies.pkgs.gh)/bin/gh \
  HERMES_TEST_GLAB=$(nix eval --raw .#nixosConfigurations.stygies.pkgs.glab)/bin/glab \
  python3 -I -B tests/test_hermes_work_cli_arity.py

Runs offline: no token, a dead proxy and an unresolvable host.
"""

import importlib.util
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


TOOL = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-work-tools.py"
spec = importlib.util.spec_from_file_location("hermes_work_tools", TOOL)
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)

UNKNOWN = ("unknown flag", "unknown shorthand flag")


class Arity(unittest.TestCase):
    def probe(self, binary, words, flag, home):
        env = {
            "PATH": os.environ.get("PATH", ""), "HOME": home, "XDG_CONFIG_HOME": f"{home}/.config",
            "HTTPS_PROXY": "http://127.0.0.1:9", "HTTP_PROXY": "http://127.0.0.1:9", "ALL_PROXY": "http://127.0.0.1:9",
            "NO_PROXY": "", "GH_HOST": "github.invalid", "GITLAB_HOST": "gitlab.invalid",
            "GH_TELEMETRY": "0", "GLAB_SEND_TELEMETRY": "0", "GLAB_CHECK_UPDATE": "false", "GLAB_NO_PROMPT": "1",
            "GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "DO_NOT_TRACK": "1",
        }
        result = subprocess.run([binary, *words, flag, "--help"], cwd=home, env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=60, check=False)
        output = result.stdout + result.stderr
        helped = result.returncode == 0 and ("USAGE" in output or "Usage" in output)
        return helped, any(text in output for text in UNKNOWN)

    def check(self, variable, specs):
        binary = os.environ.get(variable)
        if not binary:
            self.skipTest(f"{variable} not set")
        with TemporaryDirectory() as home:
            for words, command in specs.items():
                names = [(name, takes) for name, takes in command.longs.items()]
                names += [(short, command.longs[name]) for short, name in command.shorts.items()]
                for flag, takes in names:
                    with self.subTest(command=" ".join(words), flag=flag):
                        helped, unknown = self.probe(binary, words, flag, home)
                        self.assertFalse(unknown, f"{flag} does not exist")
                        self.assertEqual(not helped, takes, f"{flag}: wrapper says takes_value={takes}")

    def test_gh(self):
        self.check("HERMES_TEST_GH", tools.GH)

    def test_glab(self):
        self.check("HERMES_TEST_GLAB", tools.GLAB)


if __name__ == "__main__":
    unittest.main()
