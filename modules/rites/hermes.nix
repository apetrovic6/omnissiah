# Hermes Agent (Nous Research): an always-on agent. The gateway runs its
# cron jobs and the messaging platforms: Matrix (`matrix`, a bot account the
# homeserver registers itself), or any other whose token is in `secrets`.
# The CLI/TUI over SSH and the web dashboard work alongside.
# Packaged in llm-agents (numtide/llm-agents.nix, reached through magos),
# with Claude Code and Codex beside it as tools.
#
# How the model access splits (see the 2026-11-22 notes in memory):
#   ChatGPT plan     Hermes' own "OpenAI Codex" provider, a device-code login
#                    stored in ~/.hermes/auth.json
#   Claude plan      use the real `claude` binary (`claude -p`) for Claude Code.
#                    Hermes' native Anthropic provider is separate: OAuth may
#                    bill extra usage and must be permitted for the account.
#   API keys         `apiKeys` (the shared pi-api-keys) and `secrets`; llama-swap
#                    on phalanx as a custom OpenAI-compatible provider
#   Subagents        `profiles.<name>.delegation`: per-task tiers on an allowlist of
#                    the above (the bundled `tiers` backend, README "Hermes delegation tiers")
#
# Everything Hermes learns lives in its home: ~/.hermes (config.yaml,
# MEMORY.md, USER.md, skills, sessions, auth.json), ~/.claude and ~/.codex.
# Hermes edits its own state. Nix merges the declared profile and routing
# settings into config.yaml without replacing the rest.
# Keep a profile declared with enable = false to hide it without losing its
# state. Dropping a declaration or individual settings from Nix leaves the
# corresponding files and keys on disk. The merge prunes Nix-managed routes.
#
# One-time setup, as the hermes user (`sudo -u hermes -i`):
#   hermes model              pick providers, log in to ChatGPT (device code)
#   claude                    /login with the Claude account
#   codex login --device-auth only if the agent should drive codex directly
#   hermes                    talk to it (the TUI); sessions and memory are
#                             shared with the gateway
#
# Isolation: the hermes user has no sudo and no access to the CI microVM.
# Its cron/Kanban workers start through
# `systemd-run --user`, so they run under its user manager (hence linger),
# outside the hardening of the gateway unit below.
{self, ...}: {
  flake.nixosModules.hermes = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.hermes;
    llm = self.inputs.magos.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
    user = "hermes";
    home = "/var/lib/hermes";
    mx = cfg.matrix;
    enabledProfiles = lib.filterAttrs (_: profile: profile.enable) cfg.profiles;
    disabledProfiles = lib.attrNames (lib.filterAttrs (_: profile: !profile.enable) cfg.profiles);
    hasEnabledProfiles = enabledProfiles != {};
    claudeTokenFiles = lib.filterAttrs (_: path: path != null) (lib.mapAttrs (_: profile: profile.claudeOAuthTokenFile) enabledProfiles);
    hasClaudeTokenFiles = claudeTokenFiles != {};
    claudeTokenKey = "CLAUDE_CODE_OAUTH_TOKEN";
    # With sysusers/userborn SOPS installs service secrets as a unit, after activation.
    sopsUnitInstallsSecrets = hasClaudeTokenFiles && (config.sops.useSystemdActivation or false);
    retireUnit = "hermes-retire-profiles";
    refreshUnit = "hermes-refresh-prompts";
    # Profiles whose system prompt Nix shapes (SOUL.md, settings): the refresh unit's candidates.
    refreshProfiles = lib.attrNames enabledProfiles;
    # Switch: true also refreshes every profile's sessions on each Hermes package change (built-in
    # guidance text), at one prompt-cache miss per continuing session per upgrade. Off for now.
    refreshOnPackageChange = false;
    # Hermes 0.23.0: hermes_constants.py PROFILE_ID_RE and
    # hermes_cli/profiles.py _RESERVED_NAMES (default is not a named profile).
    profileIdPattern = "^[a-z0-9][a-z0-9_-]{0,63}$";
    reservedProfileNames = ["hermes" "default" "test" "tmp" "root" "sudo"];
    yaml = pkgs.formats.yaml {};
    # profiles.<name>.delegation -> settings.delegation for the bundled `tiers` backend
    # (_hermes-delegation-tiers). Everything below is written on every activation, tiers on or off:
    # the merge never deletes keys, so emptying the tiers, dropping the default or clearing a stale
    # route key only takes effect this way. Turning tiers off leaves the lifecycle knobs pinned
    # (max_spawn_depth, max_iterations, ...); their values are the safe ones either way.
    renderTier = tier:
      {inherit (tier) name description model;}
      // lib.optionalAttrs (tier.provider != null) {inherit (tier) provider;}
      // lib.optionalAttrs (tier.effort != null) {reasoning_effort = tier.effort;}
      // lib.optionalAttrs (tier.fallback != []) {fallback = map (step: {inherit (step) provider model;}) tier.fallback;};
    # Hermes 0.23.0 agent/delegation_provider.py ROUTE_KEYS plus the backend selection: the keys
    # that decide where a child runs. The default backend routes every child by these
    # (delegation.provider/base_url/api_key/profile), so they are pinned to "inherit the parent"
    # and may not come from `settings.delegation`.
    delegationRouteKeys = ["backend" "backends" "model" "provider" "base_url" "api_key" "api_mode" "request_overrides" "reasoning_effort" "service_tier" "fallback_providers" "profile" "label"];
    # Ids that name no single account: `auto` picks whichever login is present, `custom` any endpoint.
    metaProviders = ["auto" "custom"];
    delegationSettings = profile: let
      d = profile.delegation;
      on = d.tiers != [];
      # An empty allowlist (work) always runs the tiers backend: with no tiers it routes every child
      # on the parent's route and ignores the core route keys entirely.
      inheritOnly = d.allowedProviders == [];
    in {
      delegation = {
        backend =
          if on || inheritOnly
          then "tiers"
          else "default";
        backends.tiers = {
          allowed_providers = d.allowedProviders;
          default =
            if d.default != null
            then d.default
            else "";
          options = map renderTier d.tiers;
        };
        # Empty = inherit the parent's provider, endpoint, key and effort (the default backend's route).
        provider = "";
        model = "";
        base_url = "";
        api_key = "";
        api_mode = "";
        profile = "";
        reasoning_effort = "";
        request_overrides = {};
        # Flat delegation: children never delegate, run nothing unapproved, and fall back only
        # along their tier's own (allowlisted) chain.
        fallback_providers = [];
        max_spawn_depth = 1;
        orchestrator_enabled = false;
        subagent_auto_approve = false;
        max_concurrent_children = d.maxConcurrentChildren;
        child_timeout_seconds = d.childTimeoutSeconds;
        max_iterations = d.maxIterations;
      };
    };
    profileSettings = profile: lib.recursiveUpdate profile.settings (delegationSettings profile);
    # Read-only copy of each profile's allowlist, keyed by profile home. The backend intersects it
    # with config.yaml's, so a hand edit there can narrow a profile's providers, never widen them.
    delegationAllowlist = pkgs.writeText "hermes-delegation-allowlist.json" (builtins.toJSON (lib.mapAttrs' (name: profile:
      lib.nameValuePair "${home}/.hermes/profiles/${name}" profile.delegation.allowedProviders)
    enabledProfiles));
    delegationAssertions = name: profile: let
      d = profile.delegation;
      names = map (tier: tier.name) d.tiers;
      where = "services.imperium.hermes.profiles.${name}.delegation";
      providers = lib.concatMap (tier: lib.optional (tier.provider != null) tier.provider ++ map (step: step.provider) tier.fallback) d.tiers;
      settingsKeys = lib.attrNames (profile.settings.delegation or {});
      routeKeysSet = lib.filter (key: lib.elem key delegationRouteKeys) settingsKeys;
    in [
      {
        assertion = lib.length names == lib.length (lib.unique names);
        message = "${where}.tiers: tier names must be unique.";
      }
      {
        assertion = d.default == null || lib.elem d.default names;
        message = "${where}.default must name one of its tiers.";
      }
      {
        assertion = lib.all (provider: lib.elem provider d.allowedProviders) providers;
        message = "${where}: every tier and fallback provider must be in allowedProviders (${lib.concatStringsSep ", " d.allowedProviders}); found ${lib.concatStringsSep ", " (lib.unique providers)}.";
      }
      {
        assertion = !lib.any (provider: lib.elem provider metaProviders) (d.allowedProviders ++ providers);
        message = "${where}: ${lib.concatStringsSep " and " metaProviders} are not providers (they pick whatever login or endpoint is present); name a real provider id.";
      }
      {
        assertion = lib.all (tier: tier.provider != null || tier.fallback == []) d.tiers;
        message = "${where}.tiers: a tier on the parent's credentials (provider = null) cannot have a fallback.";
      }
      {
        assertion = routeKeysSet == [];
        message = "services.imperium.hermes.profiles.${name}.settings.delegation sets ${lib.concatStringsSep ", " routeKeysSet}, which decide where subagents run; use ${where} instead (only lifecycle knobs belong in settings).";
      }
    ];
    # One route per room. Hermes keys a conversation on the room (and thread),
    # so every room is its own conversation within the profile.
    routes = lib.concatLists (lib.mapAttrsToList (name: profile:
      lib.optionals mx.enable (lib.mapAttrsToList (room: chatId: {
          name = "nixos-matrix-${name}-${room}";
          platform = "matrix";
          profile = name;
          chat_id = chatId;
        })
        profile.rooms))
    enabledProfiles);
    profileConfig = pkgs.linkFarm "hermes-config" ([
        {
          name = "config.yaml";
          path = yaml.generate "hermes-default-config.yaml" (lib.optionalAttrs hasEnabledProfiles {
            gateway.multiplex_profiles = hasEnabledProfiles;
            gateway.profile_routes = routes;
          });
        }
      ]
      # Mixed into every profile's prompt fingerprint (_hermes-merge-config.py, PROMPT_EXTRA).
      ++ lib.optional refreshOnPackageChange {
        name = "prompt-sources-extra";
        path = pkgs.writeText "hermes-prompt-sources-extra" "${cfg.package}";
      }
      ++ lib.concatLists (lib.mapAttrsToList (name: profile:
        [
          {
            name = "profiles/${name}/config.yaml";
            path = yaml.generate "hermes-${name}-config.yaml" (profileSettings profile);
          }
        ]
        ++ lib.optional (profile.soul != null) {
          name = "profiles/${name}/SOUL.md";
          path = pkgs.writeText "hermes-${name}-SOUL.md" profile.soul;
        })
      enabledProfiles));
    configPython = pkgs.python3.withPackages (ps: [ps.ruamel-yaml]);
    profileConfigCommand = action:
      lib.escapeShellArgs [
        (lib.getExe configPython)
        ./_hermes-merge-config.py
        action
        "${home}/.hermes"
        profileConfig
      ];
    tokenArgs = lib.concatStrings (lib.mapAttrsToList (name: path: " ${lib.escapeShellArg "${name}=${path}"}") claudeTokenFiles);
    # The token half is a separate argument list: with systemd-installed secrets
    # the switch-time merge still applies config and SOUL, and leaves the dotenv
    # to the gateway start, after sops-install-secrets.service.
    applyProfileConfigWithoutTokens = profileConfigCommand "apply";
    applyProfileConfig = applyProfileConfigWithoutTokens + tokenArgs;
    tokenUnit = "hermes-work-token";
    checkClaudeTokens = profileConfigCommand "check" + tokenArgs;
    # Shared with the homeserver, which registers the account
    # (modules/noosphere/vox/matrix-bots.nix).
    mxGenerator = "matrix-bot-${mx.localpart}";

    # Generator for a Hermes-only secret: OPENROUTER_API_KEY ->
    # hermes-openrouter-api-key, one prompt each, so changing one never means
    # retyping the rest.
    generatorFor = key: "hermes-" + lib.toLower (lib.replaceStrings ["_"] ["-"] key);

    # Every key Hermes gets: the shared ones from `apiKeys`, plus `secrets`.
    allKeys =
      cfg.apiKeys
      // lib.genAttrs cfg.secrets (key: {
        generator = generatorFor key;
        file = "value";
      })
      // lib.optionalAttrs mx.enable {
        MATRIX_PASSWORD = {
          generator = mxGenerator;
          file = "password";
        };
      };
    keyPath = k: config.clan.core.vars.generators.${k.generator}.files.${k.file}.path;

    # `hermes` with its API keys exported from the secret files, for the
    # gateway and for an interactive `hermes` alike. Missing files are skipped,
    # so a key that is not generated yet only disables its provider.
    hermes = pkgs.writeShellScriptBin "hermes" ''
      ${lib.concatStrings (lib.mapAttrsToList (env: k: ''
          if [ -r ${keyPath k} ]; then
            ${env}="$(tr -d '\n' < ${keyPath k})"
            export ${env}
          fi
        '')
        allKeys)}
      # The delegation tiers backend's read-only allowlist (delegationAllowlist).
      export HERMES_DELEGATION_TIERS_ALLOWLIST=${delegationAllowlist}
      exec ${cfg.package}/bin/hermes "$@"
    '';

    # On the gateway's PATH and in the user's interactive shell alike, so a
    # tool that works when you try it by hand also works for the agent.
    tools =
      [hermes llm.claude-code llm.codex]
      ++ (with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        gawk
        diffutils
        git
        curl
        jq
        ripgrep
        nodejs
        python3
        config.nix.package
      ])
      ++ cfg.extraPackages;
    # The environment and sandbox both of its services run in.
    sessionEnv =
      {
        HOME = home;
        USER = user;
        LOGNAME = user;
        # Read by the delegation tiers backend (delegationAllowlist).
        HERMES_DELEGATION_TIERS_ALLOWLIST = "${delegationAllowlist}";
        # For `systemd-run --user` from the gateway.
        XDG_RUNTIME_DIR = "/run/user/${toString cfg.uid}";
        DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/${toString cfg.uid}/bus";
      }
      // lib.optionalAttrs (cfg.sshHostOnlyPaths != []) {
        # Read by the patched coerce_ssh_remote_cwd (_hermes-ssh-host-cwd.py).
        HERMES_SSH_HOST_ONLY_PREFIXES = lib.concatStringsSep ":" cfg.sshHostOnlyPaths;
      };
    hardening = {
      User = user;
      Group = user;
      WorkingDirectory = home;
      Restart = "on-failure";
      RestartSec = 10;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [home];
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
    };
    sessionServiceConfig =
      hardening
      // lib.optionalAttrs hasClaudeTokenFiles {
        UnsetEnvironment = claudeTokenKey;
      };
  in {
    imports = [self.nixosModules.pi-api-keys];

    options.services.imperium.hermes = {
      enable = mkEnableOption "the Hermes Agent gateway";
      package = mkOption {
        type = types.package;
        # Upstream's ssh guard (coerce_ssh_remote_cwd) maps only a container's subprocess home onto
        # the remote, so a project path Hermes normalised on this host (/var/lib/hermes/...) reached
        # the remote `cd` verbatim and every command exited 126. The patch redirects paths under
        # `sshHostOnlyPaths` to the profile's terminal.cwd; an agent's explicit workdir is left alone.
        # --replace-fail: an llm-agents bump that moves these lines fails the build, not the runtime.
        default = llm.hermes-agent.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              cp ${./_hermes-ssh-host-cwd.py} tools/nixos_ssh_host_cwd.py
              substituteInPlace tools/terminal_tool_config.py \
                --replace-fail 'def coerce_ssh_remote_cwd(cwd: str | None, env_type: str | None) -> str | None:' \
                  'def coerce_ssh_remote_cwd(cwd: str | None, env_type: str | None, *, host_guard: bool = True) -> str | None:' \
                --replace-fail '        return text or "~"
              ' \
                  '        return text or "~"
                  if host_guard:
                      from tools.nixos_ssh_host_cwd import host_only_fallback
                      if (fallback := host_only_fallback(text)) is not None:
                          return fallback
              '
              substituteInPlace tools/terminal_tool.py \
                --replace-fail 'return coerce_ssh_remote_cwd(_container_visible_cwd(workdir, env_type, env), env_type)' \
                  'return coerce_ssh_remote_cwd(_container_visible_cwd(workdir, env_type, env), env_type, host_guard=False)'
            '';
          postInstall =
            (old.postInstall or "")
            + ''
              PYTHONPATH="$(echo $out/lib/python3*/site-packages)''${PYTHONPATH:+:$PYTHONPATH}" \
                HERMES_SSH_HOST_ONLY_PREFIXES=/var/lib/hermes TERMINAL_CWD='~/launch-profile' \
                python3 -B -c 'from tools.terminal_tool_config import coerce_ssh_remote_cwd as c
              from tools.terminal_scope import _terminal_scope_var as scope
              # Unscoped, the process TERMINAL_CWD may be another profile`s: home instead.
              assert c("/var/lib/hermes/projects/rat", "ssh") == "~", c("/var/lib/hermes/projects/rat", "ssh")
              token = scope.set({"TERMINAL_CWD": "~/personal", "TERMINAL_ENV": "ssh"})
              assert c("/var/lib/hermes/projects/rat", "ssh") == "~/personal", c("/var/lib/hermes/projects/rat", "ssh")
              scope.reset(token)
              assert c("/home/hermes/personal/rat", "ssh") == "/home/hermes/personal/rat"
              assert c("/var/lib/hermes/x", "ssh", host_guard=False) == "/var/lib/hermes/x"
              assert c("/var/lib/hermes/x", "local") == "/var/lib/hermes/x"'

              # The `tiers` delegation backend (_hermes-delegation-tiers), as a bundled plugin:
              # HERMES_BUNDLED_PLUGINS is this dir, and a bundled `kind: backend` loads without
              # plugins.enabled. Inert unless a profile sets delegation.backend: tiers (`delegation`
              # option below). The smoke test runs it against this core, so a Hermes bump that
              # moves the delegation seam fails the build.
              plugins=$out/share/hermes/plugins
              chmod u+w "$plugins/delegation"
              mkdir "$plugins/delegation/tiers"
              cp ${./_hermes-delegation-tiers/plugin.yaml} "$plugins/delegation/tiers/plugin.yaml"
              cp ${./_hermes-delegation-tiers/__init__.py} "$plugins/delegation/tiers/__init__.py"
              chmod a-w "$plugins/delegation"
              smokeHome="$(mktemp -d)"
              PYTHONPATH="$(echo $out/lib/python3*/site-packages)''${PYTHONPATH:+:$PYTHONPATH}" \
                HOME="$smokeHome" HERMES_HOME="$smokeHome/.hermes" HERMES_BUNDLED_PLUGINS="$plugins" \
                python3 -B ${./_hermes-delegation-tiers-smoke.py}
              rm -rf "$smokeHome"
            '';
        });
      };
      uid = mkOption {
        type = types.int;
        default = 1100;
        description = "Fixed, so the gateway can order itself after the user's manager.";
      };
      memory = mkOption {
        type = types.int;
        default = 6;
        description = "GiB the gateway may use, its tools and subagents included.";
      };
      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [];
      };

      sshHostOnlyPaths = mkOption {
        type = types.listOf (types.strMatching "/.*[^/]");
        default = [home];
        description = ''
          Absolute paths that exist only on this host. An ssh profile's terminal and file tools
          never `cd` into them on the remote: such a cwd (a desktop project Hermes normalised
          here) falls back to the profile's terminal.cwd. Must not contain the remote user's home.
        '';
      };

      profiles = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Provision and route this profile. Disabling it preserves its files but makes it unavailable to Hermes.";
            };
            settings = mkOption {
              type = types.attrsOf yaml.type;
              default = {};
              description = "Non-secret settings merged into this named Hermes profile's config.yaml.";
            };
            claudeOAuthTokenFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Runtime file containing a raw Claude Code setup token. Merged into this enabled profile's .env, never exported by the shared Hermes wrapper.";
            };
            soul = mkOption {
              type = types.nullOr types.lines;
              default = null;
              description = "Profile SOUL.md replaced on activation and gateway startup. Null leaves the file alone.";
            };
            rooms = mkOption {
              type = types.attrsOf (types.strMatching "![^[:space:]]+");
              default = {};
              example = {pilot = "!roomid:example.org";};
              description = "Matrix rooms routed to this profile by the default bot, by a short name (used in the route name). Each room is its own conversation.";
            };
            # Rendered into settings.delegation by `delegationSettings` (README "Hermes delegation tiers").
            delegation = {
              tiers = mkOption {
                type = types.listOf (types.submodule {
                  options = {
                    name = mkOption {
                      type = types.strMatching "[a-z][a-z0-9_-]{0,31}";
                      description = "What the agent picks (`tier` on delegate_task).";
                    };
                    description = mkOption {
                      type = types.str;
                      description = "One line the agent reads to choose the tier. Never names the model.";
                    };
                    provider = mkOption {
                      type = types.nullOr (types.strMatching "[a-z0-9][a-z0-9-]*");
                      default = null;
                      description = "Canonical Hermes provider id, from allowedProviders. Null: the parent's own credentials, only the model changes.";
                    };
                    model = mkOption {type = types.str;};
                    effort = mkOption {
                      # Hermes 0.23.0 hermes_constants.VALID_REASONING_EFFORTS, plus none.
                      type = types.nullOr (types.enum ["none" "minimal" "low" "medium" "high" "xhigh" "max" "ultra"]);
                      default = null;
                    };
                    fallback = mkOption {
                      type = types.listOf (types.submodule {
                        options = {
                          provider = mkOption {type = types.strMatching "[a-z0-9][a-z0-9-]*";};
                          model = mkOption {type = types.str;};
                        };
                      });
                      default = [];
                      description = "Tried in order when the tier's model fails (rate limit, outage). Each provider must be allowed; a parent-credentials tier has none.";
                    };
                  };
                });
                default = [];
                description = "Delegation tiers, in the order the agent sees them. Empty keeps Hermes' default backend.";
              };
              default = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Tier for a delegated task that names none. Null: the parent's own route.";
              };
              allowedProviders = mkOption {
                type = types.listOf (types.strMatching "[a-z0-9][a-z0-9-]*");
                default = [];
                description = ''
                  The only providers a tier or fallback may name: canonical Hermes provider ids, never
                  `auto` or `custom`. Checked at eval time and by the backend on every task, against
                  both config.yaml and a read-only copy in the store (their intersection). Empty: parent
                  credentials only, and the profile always runs the tiers backend, so no `delegation.*`
                  key can move a child to another account.
                '';
              };
              maxConcurrentChildren = mkOption {
                type = types.ints.between 1 10;
                default = 2;
                description = ''
                  Hermes `delegation.max_concurrent_children`. Not a cap on subagents overall: it limits
                  the children of one delegate_task call, and separately the background calls running at
                  once. That background pool is shared by every profile in the gateway process, and a call
                  that finds it full runs synchronously instead of being refused. So one profile can have
                  about (N background calls + 1 inline call) x N children at once.
                '';
              };
              childTimeoutSeconds = mkOption {
                type = types.ints.unsigned;
                default = 900;
                description = "Inactivity cap per subagent (no progress for this long), not total runtime. 0: none.";
              };
              maxIterations = mkOption {
                type = types.ints.positive;
                default = 150;
                description = "Per-subagent iteration budget.";
              };
            };
          };
        });
        default = {};
        description = "Named profiles to provision under the Hermes home.";
      };

      apiKeys = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            generator = mkOption {type = types.str;};
            file = mkOption {type = types.str;};
          };
        });
        # The keys pi and omp already use (modules/cartographa, pi-api-keys),
        # under the names Hermes looks for.
        default = {
          DEEPSEEK_API_KEY = {
            generator = "pi-api-keys";
            file = "deepseek-api-key";
          };
          # pi's QWEN_TOKEN_PLAN_API_KEY: Alibaba Model Studio's token plan.
          ALIBABA_TOKEN_PLAN_API_KEY = {
            generator = "pi-api-keys";
            file = "qwen-api-key";
          };
        };
        description = ''
          Environment variable -> existing clan var file holding the raw key.
          The var must be declared on this machine, readable by the hermes
          user.
        '';
      };

      dashboard = {
        enable = mkEnableOption "the Hermes web dashboard";
        port = mkOption {
          type = types.port;
          default = 9119;
        };
        publicUrl = mkOption {
          type = types.str;
          example = "https://hermes.noosphere.uk";
          description = "Where users reach it; also the base of the OIDC callback (/auth/callback).";
        };
        oidc = {
          issuer = mkOption {
            type = types.str;
            example = "https://id.noosphere.uk";
          };
          clientId = mkOption {
            type = types.str;
            default = "hermes";
          };
        };
        allowedSources = mkOption {
          type = types.listOf types.str;
          description = "IPv4 addresses allowed to connect: the reverse proxy's.";
        };
      };

      # Chat with the agent from any Matrix app. The bot account is registered
      # by the homeserver itself (`services.imperium.matrixBots.bots` there),
      # with a generated password both machines share, so nothing is typed in.
      matrix = {
        enable = mkEnableOption "the Matrix gateway";
        homeserver = mkOption {
          type = types.str;
          example = "https://matrix.example.org";
        };
        serverName = mkOption {
          type = types.str;
          example = "example.org";
          description = "The homeserver's server_name, the part after the colon in user IDs.";
        };
        localpart = mkOption {
          type = types.str;
          default = user;
          description = "The bot's local part; must be in the homeserver's matrixBots.bots.";
        };
        allowedUsers = mkOption {
          type = types.listOf types.str;
          example = ["@me:example.org"];
          description = "Matrix IDs that may talk to the agent. Everyone else is ignored.";
        };
        deviceId = mkOption {
          type = types.str;
          default = "HERMES";
          description = "A fixed device, so encrypted rooms keep trusting the same keys across restarts.";
        };
      };

      secrets = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["OPENROUTER_API_KEY" "DISCORD_BOT_TOKEN"];
        description = ''
          Hermes-only secrets, one clan var (and prompt) each. A messaging
          platform starts only when its token is among them; add the matching
          *_ALLOWED_USERS too, or strangers get a pairing prompt.

          Change one: clan vars generate <machine> --generator hermes-<key, lower-case, dashed> --regenerate
        '';
      };
    };

    config = mkIf cfg.enable {
      assertions =
        lib.mapAttrsToList (name: _: {
          assertion = builtins.match profileIdPattern name != null && !lib.elem name reservedProfileNames;
          message = "services.imperium.hermes.profiles: '${name}' is not a valid named Hermes profile ID.";
        })
        cfg.profiles
        ++ lib.concatLists (lib.mapAttrsToList delegationAssertions cfg.profiles)
        ++ lib.optional hasClaudeTokenFiles {
          assertion = !(builtins.hasAttr claudeTokenKey allKeys);
          message = "Scoped Hermes Claude Code tokens cannot also be configured in apiKeys or secrets.";
        };

      system.build.hermesConfig = mkIf (cfg.profiles != {}) profileConfig;

      users.groups.${user} = {};
      users.users.${user} = {
        isNormalUser = true;
        inherit (cfg) uid;
        group = user;
        inherit home;
        createHome = true;
        homeMode = "700";
        description = "Hermes Agent";
        # Its cron and Kanban workers need a user manager that outlives logins.
        linger = true;
        packages = tools;
      };

      # On this machine the shared provider keys belong to hermes; on the
      # workstations they stay apetrovic's (modules/cartographa).
      clan.core.vars.generators = lib.mkMerge [
        {
          pi-api-keys.files = {
            "deepseek-api-key".owner = user;
            "qwen-api-key".owner = user;
          };
        }
        (lib.listToAttrs (map (key:
          lib.nameValuePair (generatorFor key) {
            prompts.value = {
              description = "Hermes: value of ${key}";
              type = "hidden";
            };
            files.value = {
              secret = true;
              owner = user;
            };
            script = ''cp "$prompts/value" "$out/value"'';
          })
        cfg.secrets))
        (lib.optionalAttrs mx.enable {
          ${mxGenerator} = lib.recursiveUpdate (import ../noosphere/vox/_matrix-bot-var.nix {inherit pkgs;}) {
            files.password.owner = user;
          };
        })
      ];

      # Config and SOUL are applied on every switch. The dotenv token is applied
      # here only when activation installs the secrets; with systemd-installed
      # secrets the gateway's preStart does it, after sops-install-secrets.
      system.activationScripts.hermes-config = mkIf hasEnabledProfiles {
        deps = ["users"] ++ lib.optional (hasClaudeTokenFiles && !sopsUnitInstallsSecrets && (config.system.activationScripts ? setupSecrets)) "setupSecrets";
        text = ''
          if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet local-fs.target; then
            ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- ${
            if sopsUnitInstallsSecrets
            then applyProfileConfigWithoutTokens
            else applyProfileConfig
          }
          # SOUL.md is in place now; the unit only records a refresh for profiles whose
          # prompt inputs changed. It does not exist yet on a first deploy; the
          # gateway pulls it in then (hermes-gateway wants it).
          ${lib.getExe' pkgs.systemd "systemctl"} start --no-block ${refreshUnit}.service || true
          ${lib.optionalString hasClaudeTokenFiles ''
            # Re-check the token on every switch. The unit may not exist yet
            # (first deploy); the boot/timer runs cover that.
            ${lib.getExe' pkgs.systemd "systemctl"} start --no-block ${tokenUnit}.service || true
          ''}fi
        '';
      };

      # Reports a token problem as a failed unit (-> node exporter -> the
      # HermesWorkTokenUnitFailed alert). The gateway's preStart tolerates the
      # same problems so default, coder and the app keep working, which is why
      # nothing depends on this unit and it depends on nothing but the secrets.
      systemd.services.${tokenUnit} = mkIf hasClaudeTokenFiles {
        description = "Check the Hermes work profile's Claude token";
        wantedBy = ["multi-user.target"];
        # After the gateway: its preStart writes the dotenv this unit compares. Ordering
        # only; the gateway neither wants nor waits for this unit.
        after = ["local-fs.target" "hermes-gateway.service"] ++ lib.optional sopsUnitInstallsSecrets "sops-install-secrets.service";
        wants = lib.optional sopsUnitInstallsSecrets "sops-install-secrets.service";
        unitConfig.RequiresMountsFor = [home];
        serviceConfig =
          builtins.removeAttrs hardening ["Restart" "RestartSec"]
          // {
            Type = "oneshot";
            ExecStart = checkClaudeTokens;
          };
      };
      # A failed oneshot stays failed until it runs again; this also clears it
      # once the token is fixed without waiting for a deploy.
      systemd.timers.${tokenUnit} = mkIf hasClaudeTokenFiles {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitInactiveSec = "15min";
        };
      };

      # Removing the last pin must undo the old overlay before the gateway
      # starts. A fresh unpinned install has no markers, so this does nothing.
      systemd.services.${retireUnit} = mkIf (disabledProfiles != []) {
        description = "Retire previously provisioned Hermes profiles";
        unitConfig = {
          ConditionPathExists = map (name: "|${home}/.hermes/profiles/.nixos-managed/${name}") disabledProfiles;
          RequiresMountsFor = [home];
        };
        serviceConfig =
          builtins.removeAttrs hardening ["Restart" "RestartSec"]
          // {
            Type = "oneshot";
            ExecStart = "${profileConfigCommand "retire"} ${lib.escapeShellArgs disabledProfiles}";
          };
      };

      # `hermes -p <profile> sessions refresh-prompts` once per prompt change (pending markers
      # from the merge's apply). The request is a row in the profile's state.db that sessions
      # adopt on their next turn, so the gateway may be up or down; it only has to follow the
      # SOUL.md write. Never wanted by a target and never waited on: its problems are journal
      # lines (`journalctl -u hermes-refresh-prompts`), not a failed unit, which would fail the
      # switch. A failed refresh stays pending and is retried on the next activation or start.
      systemd.services.${refreshUnit} = mkIf hasEnabledProfiles {
        description = "Refresh Hermes session prompts after a SOUL or settings change";
        # Ordering only: when both are queued, run after the gateway's preStart apply.
        after = ["hermes-gateway.service"];
        unitConfig.RequiresMountsFor = [home];
        environment = sessionEnv;
        serviceConfig =
          builtins.removeAttrs hardening ["Restart" "RestartSec"]
          // {
            Type = "oneshot";
            # "-": a non-zero exit, even a crash, is not a unit failure. 90 s per profile in the
            # script; the start timeout stays above their sum, so it never fires first.
            ExecStart = "-${profileConfigCommand "refresh"} ${lib.escapeShellArgs (["${cfg.package}/bin/hermes"] ++ refreshProfiles)}";
            TimeoutStartSec = 90 * lib.length refreshProfiles + 60;
            UnsetEnvironment = claudeTokenKey;
          };
      };

      systemd.services.hermes-gateway = {
        description = "Hermes Agent gateway";
        wantedBy = ["multi-user.target"];
        after =
          ["network-online.target" "user@${toString cfg.uid}.service"]
          ++ lib.optional (disabledProfiles != []) "${retireUnit}.service"
          ++ lib.optional sopsUnitInstallsSecrets "sops-install-secrets.service";
        requires = lib.optional (disabledProfiles != []) "${retireUnit}.service";
        wants =
          ["network-online.target" "user@${toString cfg.uid}.service"]
          ++ lib.optional sopsUnitInstallsSecrets "sops-install-secrets.service"
          # Every prompt change changes preStart, so a switch restarts the gateway and this
          # runs the refresh; weak, so a refresh problem never touches the gateway.
          ++ lib.optional hasEnabledProfiles "${refreshUnit}.service";
        path = tools;
        # Boot activation precedes local mounts, so also merge before the
        # gateway starts, once the persistent Hermes home is mounted.
        unitConfig.RequiresMountsFor = [home];
        preStart = lib.optionalString hasEnabledProfiles applyProfileConfig;
        environment =
          sessionEnv
          // lib.optionalAttrs mx.enable {
            # MATRIX_PASSWORD comes from the wrapper; the platform starts
            # once it is set.
            MATRIX_HOMESERVER = mx.homeserver;
            MATRIX_USER_ID = "@${mx.localpart}:${mx.serverName}";
            MATRIX_ALLOWED_USERS = lib.concatStringsSep "," mx.allowedUsers;
            # Element encrypts DMs by default; plain rooms still work.
            MATRIX_E2EE_MODE = "optional";
            MATRIX_DEVICE_ID = mx.deviceId;
            # Written once, when Hermes first sets up cross-signing; it is
            # what restores the bot's encryption identity if its key store is
            # ever lost.
            MATRIX_RECOVERY_KEY_OUTPUT_FILE = "${home}/.hermes/matrix-recovery-key";
          };
        serviceConfig =
          sessionServiceConfig
          // {
            ExecStart = "${hermes}/bin/hermes -p default gateway run";
            # Hermes drains cron jobs before it exits.
            TimeoutStopSec = 120;
            KillMode = "mixed";
            MemoryMax = "${toString cfg.memory}G";
          };
      };

      # The web UI, behind Traefik in the cluster (nixidy apps/cogitator/hermes)
      # at `dashboard.publicUrl`. Login is Hermes' own generic OIDC provider
      # (plugins/dashboard_auth/self_hosted) against Pocket ID: a public PKCE
      # client, admins only (tofunix pharos/clients.nix `hermes`). It switches
      # on from the two OIDC variables alone, and without a provider the
      # dashboard refuses a non-loopback bind, so it can never come up open.
      systemd.services.hermes-dashboard = mkIf cfg.dashboard.enable {
        description = "Hermes Agent dashboard";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target" "hermes-gateway.service"];
        wants = ["network-online.target"];
        path = tools;
        environment =
          sessionEnv
          // {
            HERMES_DASHBOARD_PUBLIC_URL = cfg.dashboard.publicUrl;
            HERMES_DASHBOARD_OIDC_ISSUER = cfg.dashboard.oidc.issuer;
            HERMES_DASHBOARD_OIDC_CLIENT_ID = cfg.dashboard.oidc.clientId;
          };
        serviceConfig =
          sessionServiceConfig
          // {
            ExecStart = "${hermes}/bin/hermes -p default dashboard --host 0.0.0.0 --port ${toString cfg.dashboard.port}";
            MemoryMax = "2G";
          };
      };

      # Only Traefik may reach it: cluster pods leave through whichever node
      # the Traefik pod runs on, masqueraded to that node's IP (as for
      # cerberus's node exporter, modules/rites/node-exporter.nix). Not
      # openFirewall: that would open the port to the whole LAN.
      networking.firewall.extraCommands = mkIf cfg.dashboard.enable (lib.mkAfter (lib.concatMapStrings (ip: ''
          iptables -w -A nixos-fw -p tcp --dport ${toString cfg.dashboard.port} -s ${ip}/32 -m comment --comment hermes-dashboard -j nixos-fw-accept
        '')
        cfg.dashboard.allowedSources));
    };
  };
}
