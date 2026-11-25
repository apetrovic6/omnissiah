"""The delegation tiers backend (modules/rites/_hermes-delegation-tiers), without Hermes.

The Hermes modules it imports are stubbed here; the package build runs the same backend against the real
Hermes core (the smoke test in modules/rites/hermes.nix).
"""

import importlib.util
import json
import os
import sys
import types
import unittest
import unittest.mock
from pathlib import Path
from tempfile import TemporaryDirectory

PLUGIN = Path(__file__).resolve().parents[1] / "modules/rites/_hermes-delegation-tiers/__init__.py"

# Hermes 0.23.0 aliases (providers/ profiles and hermes_cli normalisers), enough to test alias refusal.
PROFILE_ALIASES = {"codex": "openai-codex", "openai_codex": "openai-codex", "dashscope-token-plan": "alibaba-token-plan"}
MODEL_ALIASES = {"claude": "anthropic", "claude-code": "anthropic"}
KNOWN = {"anthropic", "openai-codex", "deepseek", "alibaba-token-plan"}
HOME = {"path": "/var/lib/hermes/.hermes/profiles/coder"}  # the active profile home (hermes_constants stub)


class RouteError(ValueError):
    pass


class Provider:
    def settings(self, config):
        own = (config.get("backends") or {}).get(self.name)
        return own if isinstance(own, dict) else {}


def load_plugin():
    stubs = {name: types.ModuleType(name) for name in (
        "agent", "agent.delegation_provider", "hermes_cli", "hermes_cli.models", "hermes_cli.providers", "providers",
        "hermes_constants")}
    stubs["hermes_constants"].get_hermes_home = lambda: Path(HOME["path"])
    stubs["hermes_constants"].hermes_home_key = lambda path: os.path.normpath(str(path))
    stubs["agent.delegation_provider"].DelegationProvider = Provider
    stubs["agent.delegation_provider"].DelegationRouteError = RouteError
    stubs["hermes_cli.models"].normalize_provider = lambda name: MODEL_ALIASES.get(name.strip().lower(), name.strip().lower())
    stubs["hermes_cli.providers"].normalize_provider = lambda name: name.strip().lower()

    def profile(name):
        key = PROFILE_ALIASES.get(name, name)
        return types.SimpleNamespace(name=key) if key in KNOWN else None

    stubs["providers"].get_provider_profile = profile
    saved = {name: sys.modules.get(name) for name in stubs}
    sys.modules.update(stubs)
    spec = importlib.util.spec_from_file_location("hermes_delegation_tiers", PLUGIN)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # The plugin imports normalisers lazily, so the stubs stay installed for the tests' lifetime.
    return module, saved


tiers, _saved = load_plugin()


def config(options, allowed=("anthropic", "openai-codex"), default="implement"):
    own = {"options": options, "default": default}
    if allowed is not None:
        own["allowed_providers"] = list(allowed)
    return {"backend": "tiers", "backends": {"tiers": own}}


IMPLEMENT = {"name": "implement", "description": "Planned changes.", "provider": "anthropic",
             "model": "claude-sonnet-5-5", "reasoning_effort": "medium",
             "fallback": [{"provider": "openai-codex", "model": "gpt-6.2-sol"}]}
QUICK = {"name": "quick", "description": "Mechanical work.", "model": "claude-haiku-5-5", "reasoning_effort": "low"}


class Tiers(unittest.TestCase):
    def setUp(self):
        self.backend = tiers.TiersDelegationProvider()

    def route(self, cfg, **task):
        return self.backend.route_task({"goal": "g", "context": "c", "index": 0, **task}, cfg)

    def refused(self, cfg, needle, **task):
        with self.assertRaises(RouteError) as caught:
            self.route(cfg, **task)
        self.assertIn(needle, str(caught.exception))

    def test_schema_lists_names_and_descriptions_in_order(self):
        params = self.backend.task_parameters(config([QUICK, IMPLEMENT]))
        self.assertEqual(list(params), ["tier"])
        self.assertEqual(params["tier"]["enum"], ["quick", "implement"])  # config order, not sorted
        self.assertIn("quick: Mechanical work.", params["tier"]["description"])
        self.assertNotIn("claude", params["tier"]["description"])  # models never reach the model
        again = self.backend.task_parameters(config([QUICK, IMPLEMENT]))
        self.assertEqual(json.dumps(params, sort_keys=True), json.dumps(again, sort_keys=True))

    def test_no_options_no_parameter_and_no_description(self):
        self.assertEqual(self.backend.task_parameters(config([])), {})
        self.assertEqual(self.backend.description(config([])), "")
        self.assertEqual(self.backend.task_parameters({}), {})

    def test_provider_route_with_fallback_and_label(self):
        self.assertEqual(self.route(config([IMPLEMENT]), tier="implement"), {
            "model": "claude-sonnet-5-5", "reasoning_effort": "medium", "provider": "anthropic",
            "fallback_providers": [{"provider": "openai-codex", "model": "gpt-6.2-sol"}],
            "label": "implement · claude-sonnet-5-5"})

    def test_parent_credentials_route_has_no_provider_and_empty_fallback(self):
        route = self.route(config([QUICK], allowed=[]), tier="quick")
        self.assertEqual(route, {"model": "claude-haiku-5-5", "reasoning_effort": "low",
                                 "fallback_providers": [], "label": "quick · claude-haiku-5-5"})

    def test_default_tier_and_parent_route(self):
        self.assertEqual(self.route(config([IMPLEMENT]))["model"], "claude-sonnet-5-5")
        self.assertEqual(self.route(config([IMPLEMENT], default="")), {})

    def test_unknown_or_duplicate_tier_refused(self):
        self.refused(config([IMPLEMENT]), "not configured", tier="plan")
        self.refused(config([IMPLEMENT], default="plan"), "not configured")
        self.refused(config([IMPLEMENT, dict(IMPLEMENT)]), "configured twice", tier="implement")

    def test_disallowed_provider_refused(self):
        self.refused(config([IMPLEMENT], allowed=["anthropic"]), "'openai-codex' is not allowed", tier="implement")
        self.refused(config([dict(IMPLEMENT, fallback=[])], allowed=[]), "'anthropic' is not allowed", tier="implement")

    def test_missing_allowlist_is_parent_credentials_only(self):
        self.refused(config([dict(IMPLEMENT, fallback=[])], allowed=None), "none (parent credentials only)",
                     tier="implement")
        self.assertNotIn("provider", self.route(config([QUICK], allowed=None), tier="quick"))

    def test_aliases_refused_even_when_canonical_is_allowed(self):
        for alias in ("codex", "openai_codex", "claude", "Anthropic", "claude-code"):
            entry = dict(IMPLEMENT, provider=alias, fallback=[])
            self.refused(config([entry], allowed=["anthropic", "openai-codex"]), "alias", tier="implement")
        bad_fallback = dict(IMPLEMENT, fallback=[{"provider": "codex", "model": "gpt-6.2-sol"}])
        self.refused(config([bad_fallback]), "alias", tier="implement")

    def test_padded_provider_routes_as_canonical(self):
        entry = dict(IMPLEMENT, provider="  anthropic ", fallback=[{"provider": " openai-codex", "model": "gpt-6.2-sol"}])
        route = self.route(config([entry]), tier="implement")
        self.assertEqual(route["provider"], "anthropic")
        self.assertEqual(route["fallback_providers"], [{"provider": "openai-codex", "model": "gpt-6.2-sol"}])

    def test_meta_and_unknown_providers_refused(self):
        for provider in ("auto", "custom", "openai-api", "nonsense"):
            entry = dict(IMPLEMENT, provider=provider, fallback=[])
            self.refused(config([entry], allowed=[provider]), "meta id or unknown", tier="implement")

    def test_non_mapping_settings_refused(self):
        self.refused({"backend": "tiers", "backends": {"tiers": "x"}}, "not a mapping", tier="implement")
        self.refused({"backend": "tiers", "backends": {"tiers": ["x"]}}, "not a mapping")

    def test_store_allowlist_narrows_never_widens(self):
        directory = Path(self.enterContext(TemporaryDirectory()))
        store = directory / "allowlists.json"
        store.write_text(json.dumps({"/var/lib/hermes/.hermes/profiles/coder": ["anthropic"],
                                     "/var/lib/hermes/.hermes/profiles/work": []}))
        self.enterContext(unittest.mock.patch.dict(os.environ, {tiers.ALLOWLIST_ENV: str(store)}))
        wide = config([IMPLEMENT, QUICK], allowed=["anthropic", "openai-codex", "deepseek"])
        # coder: config allows Codex, the store does not, so the fallback is refused.
        self.refused(wide, "'openai-codex' is not allowed", tier="implement")
        self.assertEqual(self.route(config([dict(IMPLEMENT, fallback=[])], allowed=["anthropic"]),
                                    tier="implement")["provider"], "anthropic")
        # work: the store pins [], so a hand-widened config.yaml still routes nothing but the parent.
        self.enterContext(unittest.mock.patch.dict(HOME, {"path": "/var/lib/hermes/.hermes/profiles/work"}))
        self.refused(config([dict(IMPLEMENT, fallback=[])], allowed=["anthropic"]), "'anthropic' is not allowed",
                     tier="implement")
        self.assertNotIn("provider", self.route(wide, tier="quick"))
        # A profile the store does not list (default) uses config.yaml alone.
        self.enterContext(unittest.mock.patch.dict(HOME, {"path": "/var/lib/hermes/.hermes"}))
        self.assertEqual(self.route(wide, tier="implement")["provider"], "anthropic")

    def test_unreadable_store_allowlist_refused(self):
        self.enterContext(unittest.mock.patch.dict(os.environ, {tiers.ALLOWLIST_ENV: "/nonexistent/allow.json"}))
        self.refused(config([IMPLEMENT]), "unreadable", tier="implement")

    def test_forbidden_entry_keys_refused(self):
        for key, value in (("base_url", "http://x/v1"), ("api_key", "k"), ("api_mode", "chat_completions"),
                           ("profile", "work"), ("service_tier", "fast"), ("request_overrides", {}),
                           ("daybreak", True), ("fallback_providers", [])):
            self.refused(config([dict(IMPLEMENT, **{key: value})]), key, tier="implement")

    def test_fallback_shape(self):
        for step in ({"provider": "openai-codex"}, {"provider": "openai-codex", "model": "m", "base_url": "u"},
                     "openai-codex/gpt"):
            self.refused(config([dict(IMPLEMENT, fallback=[step])]), "fallback[0]", tier="implement")
        self.refused(config([dict(QUICK, fallback=[{"provider": "anthropic", "model": "m"}])]),
                     "cannot have a fallback", tier="quick")

    def test_missing_model_refused(self):
        self.refused(config([dict(QUICK, model="")]), "no model", tier="quick")

    def test_bad_allowlist_refused(self):
        cfg = config([IMPLEMENT])
        cfg["backends"]["tiers"]["allowed_providers"] = "anthropic"
        self.refused(cfg, "allowed_providers", tier="implement")


if __name__ == "__main__":
    unittest.main()
