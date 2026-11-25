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

The allowlist in config.yaml can be edited by hand until the next activation resets it, so Nix also
writes each managed profile's allowlist to a read-only store file named by ``HERMES_DELEGATION_TIERS_ALLOWLIST``
(``{profile home: [providers]}``). The effective allowlist is the intersection: a hand edit can narrow a
profile's providers, never widen them. A profile the file does not list (``default``) uses config.yaml alone.
The variable set but blank, or the file unreadable, refuses every tier that names a provider (fail closed);
tiers on the parent's credentials never read it.
"""

from __future__ import annotations

import json
import os
import re
from typing import Any, Callable, Mapping, Optional

from agent.delegation_provider import DelegationProvider, DelegationRouteError

BACKEND = "tiers"
PARAMETER = "tier"
SETTINGS_PATH = f"delegation.backends.{BACKEND}"
NAME_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
#: The only keys a tier may have. Anything else (base_url, api_key, api_mode, profile, service_tier,
#: request_overrides, daybreak, ...) refuses the tier: those would leave the allowlist's reach.
ENTRY_KEYS = frozenset({"name", "description", "provider", "model", "reasoning_effort", "fallback"})
FALLBACK_KEYS = frozenset({"provider", "model"})
#: Ids that name no single account: ``auto`` picks whichever login is present, ``custom`` any endpoint.
META_PROVIDERS = frozenset({"auto", "custom"})
ALLOWLIST_ENV = "HERMES_DELEGATION_TIERS_ALLOWLIST"


def _text(value: Any) -> str:
    return " ".join(value.split()) if isinstance(value, str) else ""


def _canonical(provider: str) -> Optional[str]:
    """The canonical id every Hermes normaliser agrees on, or None for an alias (``codex``, ``claude``: every
    normaliser must map the id to itself) and for an id with no provider profile (``auto``, ``custom``,
    a typo). Config must name the canonical id of a real provider."""
    from hermes_cli.models import normalize_provider as models_normalize
    from hermes_cli.providers import normalize_provider as providers_normalize
    from providers import get_provider_profile
    key = provider.strip()
    if key in META_PROVIDERS:
        return None
    profile = get_provider_profile(key)
    if profile is None:
        return None
    seen = {key, models_normalize(key), providers_normalize(key), profile.name}
    return key if seen == {key} else None


def _store_allowed() -> Optional[frozenset[str]]:
    """This profile's allowlist from the Nix store file, or None when the variable is unset or the file does not
    list this profile. The variable set but blank, or a file that is unreadable, refuses the task (fail closed)."""
    raw = os.environ.get(ALLOWLIST_ENV)
    if raw is None:
        return None
    path = raw.strip()
    if not path:
        raise DelegationRouteError(
            f"{ALLOWLIST_ENV} is set but blank, so this profile's provider allowlist cannot be checked; no "
            f"subagent was started. Use a tier without a provider, or ask the user to fix the environment.")
    try:
        with open(path, encoding="utf-8") as stream:
            data = json.load(stream)
        if not isinstance(data, dict):
            raise ValueError("not a JSON object")
    except (OSError, ValueError) as exc:
        raise DelegationRouteError(
            f"The delegation allowlist {path} ({ALLOWLIST_ENV}) is unreadable ({exc}); no subagent was started.") from exc
    from hermes_constants import get_hermes_home, hermes_home_key
    here = hermes_home_key(get_hermes_home())
    for home, providers in data.items():
        if hermes_home_key(home) == here:
            if not isinstance(providers, list) or not all(isinstance(p, str) for p in providers):
                raise DelegationRouteError(f"The delegation allowlist {path} is malformed for {home}.")
            return frozenset(p.strip() for p in providers)
    return None


def _allowed(settings: Mapping[str, Any]) -> frozenset[str]:
    raw = settings.get("allowed_providers")
    if raw is None:
        allowed = frozenset()
    elif not isinstance(raw, list) or not all(isinstance(p, str) and p.strip() for p in raw):
        raise DelegationRouteError(f"{SETTINGS_PATH}.allowed_providers must be a list of provider ids.")
    else:
        allowed = frozenset(p.strip() for p in raw)
    pinned = _store_allowed()
    return allowed if pinned is None else allowed & pinned


def _check_provider(tier: str, provider: Any, allowed: frozenset[str], where: str) -> str:
    if not isinstance(provider, str) or not provider.strip():
        raise DelegationRouteError(f"Tier {tier!r}: {where} needs a provider id.")
    canonical = _canonical(provider)
    if canonical is None:
        raise DelegationRouteError(
            f"Tier {tier!r}: {where} names provider {provider!r}, which is an alias, a meta id or unknown; "
            f"{SETTINGS_PATH} must use the canonical id of a real provider.")
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


def build_route(entry: Mapping[str, Any], allowed_fn: Callable[[], frozenset[str]]) -> dict[str, Any]:
    """The core route for one tier entry, or :class:`DelegationRouteError` naming what is wrong with it.
    ``allowed_fn`` gives the effective allowlist; it is only called when the tier names a provider."""
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
        route["provider"] = _check_provider(tier, provider, allowed_fn(), "the tier")
    chain = []
    for i, step in enumerate(fallback):
        if not isinstance(step, Mapping) or set(step) != FALLBACK_KEYS or not _text(step.get("model")):
            raise DelegationRouteError(
                f"Tier {tier!r}: fallback[{i}] must be exactly {{provider, model}}; the tier is disabled.")
        chain.append({"provider": _check_provider(tier, step["provider"], allowed_fn(), f"fallback[{i}]"),
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
        raw = (config.get("backends") or {}).get(BACKEND) if isinstance(config.get("backends"), Mapping) else None
        if raw is not None and not isinstance(raw, Mapping):
            raise DelegationRouteError(f"{SETTINGS_PATH} is not a mapping; no subagent was started.")
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
        return build_route(matches[0], lambda: _allowed(settings))


def register(ctx) -> None:
    ctx.register_delegation_provider(TiersDelegationProvider())
