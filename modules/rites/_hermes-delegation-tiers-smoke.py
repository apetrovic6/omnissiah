"""Build-time check of the bundled `tiers` delegation backend against the real Hermes core.

Run by the Hermes package's postInstall (modules/rites/hermes.nix) with HERMES_BUNDLED_PLUGINS pointing at
the output's plugin dir and HOME/HERMES_HOME at an empty temp dir. A Hermes bump that moves the delegation
seam fails the build here, not the gateway at runtime. No network, no credentials: routes are checked up to
core's parameter validation (`_route_one`), before credential resolution.
"""

from agent.delegation_provider import DelegationRouteError
from agent.delegation_registry import backend_status
from hermes_cli.plugins_discovery import collect_directory_manifests, gate_manifest, resolve_manifest_winners
from tools.delegate_tool_routes import _check_backend_effort, _declared_parameters, _route_one, schema_extension

manifest = resolve_manifest_winners(collect_directory_manifests()).get("delegation/tiers")
assert manifest is not None, "delegation/tiers is not among the bundled plugins"
assert manifest.kind == "backend", manifest.kind
assert gate_manifest(manifest, set(), None).action == "load_now", "a bundled backend must auto-load"

provider, reason = backend_status("tiers")
assert provider is not None and not reason, reason

config = {
    "backend": "tiers",
    "backends": {"tiers": {
        "allowed_providers": ["anthropic", "openai-codex"],
        "default": "implement",
        "options": [
            {"name": "implement", "description": "Planned changes.", "provider": "anthropic",
             "model": "claude-sonnet-5-5", "reasoning_effort": "medium",
             "fallback": [{"provider": "openai-codex", "model": "gpt-6.2-sol"}]},
            {"name": "quick", "description": "Mechanical work.", "model": "claude-haiku-5-5",
             "reasoning_effort": "low"},
            {"name": "aliased", "description": "x", "provider": "codex", "model": "gpt-6.2-sol"},
            {"name": "other", "description": "x", "provider": "deepseek", "model": "deepseek-flash"},
            {"name": "endpoint", "description": "x", "base_url": "http://127.0.0.1:1/v1", "model": "m"},
            {"name": "typo", "description": "x", "provider": "anthropic", "model": "m", "reasoning_effort": "hgh"},
        ],
    }},
}

params, addendum = schema_extension(config)
assert params["tier"]["enum"] == ["implement", "quick", "aliased", "other", "endpoint", "typo"], params
assert "SOUL.md" in addendum, addendum
declared = _declared_parameters(provider, config)


def route(**task):
    result = _route_one(provider, declared, 0, {"goal": "g", **task}, config)
    _check_backend_effort(0, result, config)
    return result


def refused(needle, **task):
    try:
        route(**task)
    except DelegationRouteError as exc:
        assert needle in str(exc), (needle, str(exc))
        return
    raise AssertionError(f"{task} was not refused")


assert route(tier="implement") == {
    "model": "claude-sonnet-5-5", "reasoning_effort": "medium", "provider": "anthropic",
    "fallback_providers": [{"provider": "openai-codex", "model": "gpt-6.2-sol"}],
    "label": "implement · claude-sonnet-5-5"}, route(tier="implement")
assert route()["model"] == "claude-sonnet-5-5"  # default tier
assert "provider" not in route(tier="quick")  # parent credentials
refused("alias", tier="aliased")  # core's profile registry maps codex -> openai-codex
refused("not allowed", tier="other")
refused("base_url", tier="endpoint")
refused("unknown reasoning_effort", tier="typo")  # core's effort check
refused("must be one of", tier="nope")  # core's enum check, before route_task
refused("does not take", priority="high")  # a parameter no backend declares
# A task-level model (a reserved, core-owned name) never overrides the tier's model.
assert route(tier="quick", model="gpt-6.2-sol", provider="openai-codex")["model"] == "claude-haiku-5-5"
print("delegation tiers smoke: ok")
