"""Delegation tiers (``delegation.backend: tiers``), bundled into our Hermes package (modules/rites/hermes.nix).

``delegate_task`` gains a per-task ``tier`` enum. Each tier is a model and reasoning effort, either on
a provider from the profile's allowlist or on the parent's own credentials (no ``provider``: the child
keeps the parent's exact credential bundle and only swaps the model). Settings, written by Nix
(``profiles.<name>.delegation``)::

    delegation:
      backend: tiers
      backends:
        tiers:
          allowed_providers: [anthropic, openai-codex]   # canonical ids; [] or missing = parent credentials only
          default: implement                             # tier for tasks that set none; "" = parent's route
          options:
            - name: review
              description: Independent review of the finished diff before the PR.
              provider: anthropic                        # omit = parent's credentials
              model: claude-opus-5-5
              reasoning_effort: high
              fallback: [{provider: openai-codex, model: gpt-6.2-sol}]

Same contract and config shape as NousResearch's ``advanced-delegation`` ``model_map`` backend
(hermes-official-plugins), plus what that one lacks for our billing split:

* a provider allowlist, checked on every task, so the work profile can never reach a personal login
  (a profile with no grant of its own borrows the root store's Codex grant, hermes_cli/auth.py);
* no endpoints, keys, profile hops or speed tiers in a tier: those keys refuse it;
* fail closed: an unknown tier or a bad entry refuses the task instead of running it on another route;
* every route carries an explicit fallback chain (``[]`` by default), so a child never inherits one.

Only tier names and descriptions reach the model. No slash command or CLI: Nix owns these settings.
"""

from __future__ import annotations

import re
from typing import Any, Mapping, Optional

from agent.delegation_provider import DelegationProvider, DelegationRouteError

BACKEND = "tiers"
PARAMETER = "tier"
SETTINGS_PATH = f"delegation.backends.{BACKEND}"
NAME_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
#: The only keys a tier may have. Anything else (base_url, api_key, api_mode, profile, service_tier,
#: request_overrides, daybreak, ...) refuses the tier: those would leave the allowlist's reach.
ENTRY_KEYS = frozenset({"name", "description", "provider", "model", "reasoning_effort", "fallback"})
FALLBACK_KEYS = frozenset({"provider", "model"})


def _text(value: Any) -> str:
    return " ".join(value.split()) if isinstance(value, str) else ""


def _canonical(provider: str) -> Optional[str]:
    """The canonical id every Hermes normaliser agrees on, or None when one of them maps ``provider`` to
    another id (an alias such as ``codex`` or ``claude``). Config must name the canonical id itself."""
    from hermes_cli.models import normalize_provider as models_normalize
    from hermes_cli.providers import normalize_provider as providers_normalize
    from providers import get_provider_profile
    key = provider.strip()
    profile = get_provider_profile(key)
    seen = {key, models_normalize(key), providers_normalize(key)}
    if profile is not None:
        seen.add(profile.name)
    return key if seen == {key} else None


def _allowed(settings: Mapping[str, Any]) -> frozenset[str]:
    raw = settings.get("allowed_providers")
    if raw is None:
        return frozenset()
    if not isinstance(raw, list) or not all(isinstance(p, str) and p.strip() for p in raw):
        raise DelegationRouteError(f"{SETTINGS_PATH}.allowed_providers must be a list of provider ids.")
    return frozenset(p.strip() for p in raw)


def _check_provider(tier: str, provider: Any, allowed: frozenset[str], where: str) -> str:
    if not isinstance(provider, str) or not provider.strip():
        raise DelegationRouteError(f"Tier {tier!r}: {where} needs a provider id.")
    canonical = _canonical(provider)
    if canonical is None:
        raise DelegationRouteError(
            f"Tier {tier!r}: {where} names provider {provider!r} by an alias; {SETTINGS_PATH} must use the "
            f"canonical provider id.")
    if canonical not in allowed:
        listed = ", ".join(sorted(allowed)) or "none (parent credentials only)"
        raise DelegationRouteError(
            f"Tier {tier!r}: provider {canonical!r} is not allowed in this profile (allowed: {listed}). "
            f"Pick another tier.")
    return canonical


def options(settings: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    """The configured tier entries in config order (unvalidated beyond being mappings with a name)."""
    raw = settings.get("options")
    if not isinstance(raw, list):
        return []
    return [entry for entry in raw if isinstance(entry, Mapping) and NAME_RE.match(_text(entry.get("name")))]


def build_route(entry: Mapping[str, Any], allowed: frozenset[str]) -> dict[str, Any]:
    """The core route for one tier entry, or :class:`DelegationRouteError` naming what is wrong with it."""
    tier = _text(entry.get("name"))
    extra = sorted(str(key) for key in entry if key not in ENTRY_KEYS)
    if extra:
        raise DelegationRouteError(
            f"Tier {tier!r} sets {', '.join(extra)}, which {SETTINGS_PATH} does not allow; the tier is disabled.")
    model = _text(entry.get("model"))
    if not model:
        raise DelegationRouteError(f"Tier {tier!r} has no model; the tier is disabled.")
    route: dict[str, Any] = {"model": model}
    effort = entry.get("reasoning_effort")
    if effort not in (None, ""):
        route["reasoning_effort"] = effort  # core validates the level and refuses an unknown one
    provider = entry.get("provider")
    fallback = entry.get("fallback") or []
    if not isinstance(fallback, list):
        raise DelegationRouteError(f"Tier {tier!r}: fallback must be a list of {{provider, model}} entries.")
    if provider in (None, ""):
        # Parent credentials: the child keeps the parent's provider, endpoint and key, swapping only the
        # model. A fallback needs a provider of its own, so none is allowed here.
        if fallback:
            raise DelegationRouteError(
                f"Tier {tier!r} uses the parent's credentials and cannot have a fallback; the tier is disabled.")
    else:
        route["provider"] = _check_provider(tier, provider, allowed, "the tier")
    chain = []
    for i, step in enumerate(fallback):
        if not isinstance(step, Mapping) or set(step) != FALLBACK_KEYS or not _text(step.get("model")):
            raise DelegationRouteError(
                f"Tier {tier!r}: fallback[{i}] must be exactly {{provider, model}}; the tier is disabled.")
        chain.append({"provider": _check_provider(tier, step["provider"], allowed, f"fallback[{i}]"),
                      "model": _text(step["model"])})
    route["fallback_providers"] = chain  # explicit, so the child never inherits delegation.fallback_providers
    route["label"] = f"{tier} · {model}"
    return route


class TiersDelegationProvider(DelegationProvider):
    """``delegation.backend: tiers``: the model picks a named tier per subagent."""

    @property
    def name(self) -> str:
        return BACKEND

    @property
    def display_name(self) -> str:
        return "Tiers"

    @property
    def summary(self) -> str:
        return "The agent picks a tier (model + effort on an allowlisted provider) for each subagent."

    def task_parameters(self, config: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
        entries = options(self.settings(config))
        if not entries:
            return {}
        names = list(dict.fromkeys(_text(entry.get("name")) for entry in entries))
        descriptions = {}
        for entry in entries:
            descriptions.setdefault(_text(entry.get("name")), _text(entry.get("description")))
        lines = ["Which tier runs this subagent. Omit for the profile's default tier.",
                 *(f"{name}: {descriptions[name]}" for name in names)]
        return {PARAMETER: {"type": "string", "enum": names, "description": "\n".join(lines)}}

    def description(self, config: Mapping[str, Any]) -> str:
        if not options(self.settings(config)):
            return ""
        return ("Set `tier` per task to pick its model. Subagents do not see your SOUL.md: put the rules they "
                "must follow in each task's `context`.")

    def route_task(self, task: Mapping[str, Any], config: Mapping[str, Any]) -> dict[str, Any]:
        settings = self.settings(config)
        chosen = _text(task.get(PARAMETER)) or _text(settings.get("default"))
        if not chosen:
            return {}  # the parent's own route
        matches = [entry for entry in options(settings) if _text(entry.get("name")) == chosen]
        if not matches:
            raise DelegationRouteError(
                f"Tier {chosen!r} is not configured in this profile (its tiers changed since this session "
                f"started). Use a listed tier, or ask the user to start a new session with /new.")
        if len(matches) > 1:
            raise DelegationRouteError(f"Tier {chosen!r} is configured twice; the tier is disabled.")
        return build_route(matches[0], _allowed(settings))


def register(ctx) -> None:
    ctx.register_delegation_provider(TiersDelegationProvider())
