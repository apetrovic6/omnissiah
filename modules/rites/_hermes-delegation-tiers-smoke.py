"""Build-time check of the bundled `tiers` delegation backend against the real Hermes core.

Run by the Hermes package's postInstall (modules/rites/hermes.nix) with HERMES_BUNDLED_PLUGINS pointing at
the output's plugin dir and HOME/HERMES_HOME at an empty temp dir. A Hermes bump that moves the delegation
seam fails the build here, not the gateway at runtime. No network, no credentials: routes are checked through
core's parameter validation (`_route_one`), and parent-credential routes through core's credential and runtime
resolution with a fake parent, because the work profile's isolation rests on that core behaviour:
(a) a route with no provider or endpoint resolves to an empty override bundle, (b) the child then takes the
parent's provider and key, (c) an explicit empty fallback chain beats the parent's, (d) a session routes on
the backend it was built with.
"""

import json
import os
import tempfile

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
            {"name": "meta", "description": "x", "provider": "auto", "model": "m"},
            {"name": "custom", "description": "x", "provider": "custom", "model": "m"},
        ],
    }},
}

params, addendum = schema_extension(config)
assert params["tier"]["enum"] == ["implement", "quick", "aliased", "other", "endpoint", "typo", "meta", "custom"], params
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
refused("meta id", tier="meta")  # `auto` has no provider profile in this core
refused("meta id", tier="custom")  # `custom` has one in this core: only META_PROVIDERS refuses it
refused("must be one of", tier="nope")  # core's enum check, before route_task
refused("does not take", priority="high")  # a parameter no backend declares
# A task-level model (a reserved, core-owned name) never overrides the tier's model.
assert route(tier="quick", model="gpt-6.2-sol", provider="openai-codex")["model"] == "claude-haiku-5-5"

# The read-only store allowlist, keyed by this core's hermes_home_key of the profile home: it narrows.
from hermes_constants import get_hermes_home  # noqa: E402

with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as stream:
    json.dump({str(get_hermes_home()): ["anthropic"]}, stream)
os.environ["HERMES_DELEGATION_TIERS_ALLOWLIST"] = stream.name
refused("'openai-codex' is not allowed", tier="implement")  # the Codex fallback is no longer allowed
assert "provider" not in route(tier="quick")
os.environ["HERMES_DELEGATION_TIERS_ALLOWLIST"] = " "
refused("set but blank", tier="implement")  # present but blank: fail closed for provider tiers
assert "provider" not in route(tier="quick")
del os.environ["HERMES_DELEGATION_TIERS_ALLOWLIST"]
os.unlink(stream.name)

# (a)-(d): parent-credential routes against core's resolution, with a fake parent (no network).
from tools.delegate_tool_config import _resolve_child_runtime, _resolve_delegation_credentials  # noqa: E402
from tools.delegate_tool_routes import resolve_task_routes  # noqa: E402


class Parent:
    provider = "anthropic"
    requested_provider = "anthropic"
    model = "claude-opus-5-5"
    base_url = "https://api.anthropic.com"
    api_key = "sk-ant-oat01-PARENT"
    api_mode = "anthropic_messages"
    _fallback_chain = [{"provider": "openai-codex", "model": "gpt-6.2-sol"}]
    acp_command = None
    acp_args = []
    reasoning_config = None
    request_overrides = {}
    capabilities = None
    _client_kwargs = None
    client = None


quick = route(tier="quick")
creds = _resolve_delegation_credentials(quick, Parent())
assert (creds["provider"], creds["base_url"], creds["api_key"]) == (None, None, None), creds  # (a)
assert creds["model"] == "claude-haiku-5-5", creds
runtime = _resolve_child_runtime(
    Parent(), {}, Parent.api_key, model=creds["model"], override_provider=None, override_base_url=None,
    override_api_key=None, override_api_mode=None, override_acp_command=None, override_acp_args=None,
    routing_cfg=quick, override_reasoning_effort="low")
assert runtime["provider"] == "anthropic" and runtime["api_key"] == Parent.api_key, runtime["provider"]  # (b)
assert not runtime["fallback_model"], runtime["fallback_model"]  # (c) the route's [] beats the parent's chain

# (d) A session built on `tiers` keeps routing on it after config.yaml switches to default, and back.
pinned_parent = Parent()
pinned_parent._delegation_backend = "tiers"
routes, error = resolve_task_routes([{"goal": "g", "tier": "quick"}], {**config, "backend": "default"}, pinned_parent)
assert error is None and routes[0].error is None, (error, routes and routes[0].error)
assert routes[0].report() == {"backend": "tiers", "label": "quick · claude-haiku-5-5"}, routes[0].report()
pinned_parent._delegation_backend = "default"
routes, error = resolve_task_routes([{"goal": "g", "tier": "quick"}], config, pinned_parent)
assert error is None and routes[0].error and "does not take" in routes[0].error, routes[0].error

# The default backend with the route keys Nix pins (work's config before any tiers): parent credentials.
default_cfg = {"backend": "default", "provider": "", "model": "", "base_url": "", "api_key": "", "api_mode": "",
               "profile": "", "reasoning_effort": "", "request_overrides": {}, "fallback_providers": []}
default_parent = Parent()
default_parent._delegation_backend = "default"
routes, error = resolve_task_routes([{"goal": "g"}], default_cfg, default_parent)
assert error is None and routes[0].error is None and routes[0].profile_home is None, routes[0].error
assert (routes[0].creds["provider"], routes[0].creds["base_url"], routes[0].creds["api_key"]) == (None, None, None)
print("delegation tiers smoke: ok")
