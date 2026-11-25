# The always-on agent (modules/rites/hermes.nix), on the host side of ryza.
# Each forge gets its own CI microVM (./forgejo-runner.nix), so jobs never
# share a kernel with the logins in /var/lib/hermes. Guest RAM totals 14 of
# Ryza's 24 GiB before QEMU overhead; the Hermes gateway is capped at 6.
#
# API keys: the DeepSeek and Qwen keys pi already uses (shared var
# pi-api-keys), by default. Hermes-only ones go in `secrets`, one prompt each:
#   secrets = ["OPENROUTER_API_KEY"];
#   clan vars generate ryza --generator hermes-openrouter-api-key --regenerate
{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (import ../../modules/cartographa/_cartographa.nix) noosphere lab;
  inherit (self.lib.hosts) stygies;
  inherit (config.services.imperium.hermes.stygies) knownHosts;
  hasHostPin = knownHosts != "";
  hostKeyAlgorithm = builtins.head (lib.splitString " " knownHosts);
  inherit (import ./_coder-projects.nix) forges projects;
  projectNames = lib.attrNames projects;
  sshTerminal = {
    backend = "ssh";
    ssh_host = stygies;
    ssh_user = "hermes";
    ssh_key = config.clan.core.vars.generators.hermes-stygies-ssh.files."id_ed25519".path;
  };
  # Every auxiliary slot Hermes 0.23.0 defaults to "auto" (hermes_cli/config_defaults.py,
  # `auxiliary`). Pinned for work: auto-chains (the vision one has no discovery gate,
  # agent/auxiliary_client.py) could reach a provider logged in under default.
  workAuxiliarySlots = [
    "vision"
    "compression"
    "approval"
    "review"
    "mcp"
    "title_generation"
    "memory_query_rewrite"
    "tts_audio_tags"
    "voice_chat"
    "triage_specifier"
    "kanban_decomposer"
    "profile_describer"
    "goal_judge"
    "group_router"
    "curator"
    "monitor"
    "background_review"
    "moa_reference"
    "moa_aggregator"
  ];
  workModel = {
    provider = "anthropic";
    model = "claude-opus-5-5";
  };
  # Delegation tiers (modules/rites/_hermes-delegation-tiers; README "Hermes delegation tiers").
  # Which Alibaba Token Plan endpoint the pi-api-keys Qwen key belongs to: "alibaba-token-plan"
  # (Singapore) or "alibaba-token-plan-cn" (Beijing). The README says how to check.
  qwenTokenPlanProvider = "alibaba-token-plan";
  # Personal subscriptions and keys: the Claude Code login (Max), the ChatGPT Plus device login in
  # the root auth.json, and the pi-api-keys DeepSeek and Qwen keys. A fallback runs at its tier's
  # effort: Hermes fallback entries are provider + model only.
  coderTiers = [
    {
      name = "plan";
      description = "A hard design question inside an approved task: a cross-cutting change, an unclear root cause, or two viable approaches to weigh.";
      provider = "anthropic";
      model = "claude-fable-5-2";
      effort = "high";
      fallback = [
        {
          provider = "anthropic";
          model = "claude-opus-5-5";
        }
      ];
    }
    {
      name = "implement";
      description = "A well-specified change you already planned: files, approach and tests named in the goal.";
      provider = "anthropic";
      model = "claude-sonnet-5-5";
      effort = "medium";
      # Terra (fast, efficient) for when Sol's 5-hour Plus window is spent.
      fallback = [
        {
          provider = "openai-codex";
          model = "gpt-6.2-sol";
        }
        {
          provider = "openai-codex";
          model = "gpt-6.1-terra";
        }
      ];
    }
    {
      name = "review";
      description = "Independent review of the finished diff before the PR: bugs, missing tests, rule violations. Once per PR.";
      provider = "anthropic";
      model = "claude-opus-5-5";
      effort = "high";
      fallback = [
        {
          provider = "openai-codex";
          model = "gpt-6.2-sol";
        }
      ];
    }
    {
      name = "quick";
      description = "Mechanical, read-only work: find usages, summarise a file or log, draft a commit message or PR body for the parent to use.";
      provider = "anthropic";
      model = "claude-haiku-5-5";
      effort = "low";
      # Luna costs little of the Plus window; DeepSeek (pay per token) last.
      fallback = [
        {
          provider = "openai-codex";
          model = "gpt-6-luna";
        }
        {
          provider = "deepseek";
          model = "deepseek-flash";
        }
      ];
    }
    {
      name = "bulk";
      description = "Reading a lot of text: long logs, large diffs, many files, where the answer is a short summary. Never for code you will push.";
      provider = "deepseek";
      model = "deepseek-v4-pro";
      effort = "high";
      fallback = [
        {
          provider = qwenTokenPlanProvider;
          model = "qwen3.8-max";
        }
      ];
    }
  ];
  # Work: the DevZero token only. Every tier keeps the parent's credentials (provider = null) and
  # changes the model, so a child can't reach a personal login: a profile with no Codex grant of
  # its own borrows the root store's (hermes_cli/auth.py), whatever auth.adopt_external_logins says.
  # Off until manjo enables work delegation; the assertion below holds either way.
  workTiersEnabled = false;
  workTiers = [
    {
      name = "plan";
      description = "A hard design question inside an approved task: a cross-cutting change, an unclear root cause, or two viable approaches to weigh.";
      model = "claude-opus-5-5";
      effort = "xhigh";
    }
    {
      name = "implement";
      description = "A well-specified change you already planned: files, approach and tests named in the goal.";
      model = "claude-sonnet-5-5";
      effort = "medium";
    }
    {
      name = "review";
      description = "Independent review of the finished diff before the PR: bugs, missing tests, rule violations. Once per PR.";
      model = "claude-opus-5-5";
      effort = "high";
    }
    {
      name = "quick";
      description = "Mechanical, read-only work: find usages, summarise a file or log, draft a commit message or PR body for the parent to use.";
      model = "claude-haiku-5-5";
      effort = "low";
    }
  ];
  appProjectRule =
    if projectNames == []
    then "No app repos are enabled; do not claim app tasks."
    else "Manjo must name the exact repo: ${lib.concatMapStringsSep ", " (repo: "`${repo}`") projectNames}. If unclear or unlisted, ask before claiming or planning.";
  projectRoutes = lib.concatStringsSep "\n" (lib.mapAttrsToList (repo: project: let
    forge = forges.${project.forge};
  in "| `${repo}` | `${project.owner or "manjo"}` | `${project.room}` | `${forge.gitBase}` | `${forge.host}` |")
  projects);
  # Work coder (HOM-36): rendered from _work-projects.nix.
  workCoder = config.services.imperium.hermes.workCoder;
  workCompanies = (import ./_work-projects.nix).check workCoder.companies;
  forgeLabel = company:
    if company.kind == "github"
    then "GitHub `${company.host}`"
    else "GitLab `${company.host}`";
  code = text: "`${text}`";
  workCompanyRows = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: company: let
    cli =
      if company.kind == "github"
      then "gh"
      else "glab";
    jira =
      if company.jiraProjects == []
      then "none configured: ask manjo"
      else lib.concatMapStringsSep ", " code company.jiraProjects;
  in
    if company.enabled
    then "| ${name} | `${company.room}` | ${forgeLabel company} | `${name}-task-*` | `${name}-${cli}` | ${jira} | `${workCoder.identityFiles.${name}}` |"
    else "| ${name} | `${company.room}` | ${forgeLabel company} | not enabled | — | — | — |")
  workCompanies);
  workRepoRows = let
    rows = lib.concatLists (lib.mapAttrsToList (name: company:
      lib.mapAttrsToList (key: repo: "| ${name} | `${key}` | `${repo.path}` | `https://${company.host}/${repo.path}.git` |") company.repos)
    workCompanies);
    empty = lib.attrNames (lib.filterAttrs (_: company: company.repos == {}) workCompanies);
  in
    lib.concatStringsSep "\n" (lib.optionals (rows != []) (["| Company | Repo key | Path | Clone URL |" "| --- | --- | --- | --- |"] ++ rows)
      ++ lib.optional (empty != []) "${lib.optionalString (rows != []) "\n"}No repos are enabled for ${lib.concatStringsSep " or " empty}; do not claim tasks there. Manjo adds repos in `_work-projects.nix` (README, \"Hermes work coder\").");
in {
  imports = [
    self.nixosModules.hermes
    ../../modules/rites/_hermes-stygies-ssh.nix
  ];

  options.services.imperium.hermes.workCoder = {
    companies = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = (import ./_work-projects.nix).companies;
      description = "Work coder companies (_work-projects.nix); an option only so checks can evaluate other values.";
    };
    identityFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      # Stygies's Git identity var paths (only its terminal reads them), for
      # the SOUL's check. Lazy: only enabled companies have the var.
      default = lib.mapAttrs (_: company: self.nixosConfigurations.stygies.config.clan.core.vars.generators.${company.identityGenerator}.files.gitconfig.path) workCoder.companies;
      description = "Per company, the stygies path of its Git identity file.";
    };
  };

  options.services.imperium.hermes.stygies.knownHosts = lib.mkOption {
    type = lib.types.str;
    description = "Verified stygies SSH host public key (type and base64, without a hostname). Empty disables coder and the work terminal.";
    # stygies's own host key, from the clan var its sshd was deployed with,
    # so the pin follows a reinstall instead of going stale. The value ends in
    # an empty comment; keep only the type and the key. Empty until the var exists.
    default = let
      pub = self.lib.vars.machine "stygies" "openssh" "ssh.id_ed25519.pub";
    in
      if builtins.pathExists pub
      then lib.concatStringsSep " " (lib.take 2 (lib.filter (s: s != "") (lib.splitString " " (lib.trim (builtins.readFile pub)))))
      else "";
  };

  config = {
    assertions = [
      {
        assertion = !hasHostPin || hostKeyAlgorithm == "ssh-ed25519";
        message = "services.imperium.hermes.stygies.knownHosts must be an ssh-ed25519 host key.";
      }
      {
        # The guard redirects any ssh cwd under these paths; the remote home must stay outside them.
        assertion = let
          remoteHome = self.nixosConfigurations.stygies.config.users.users.hermes.home;
        in
          !lib.any (path: remoteHome == path || lib.hasPrefix "${path}/" remoteHome) config.services.imperium.hermes.sshHostOnlyPaths;
        message = "services.imperium.hermes.sshHostOnlyPaths must not contain stygies's hermes home, or every coder and work command would leave its workspace.";
      }
      {
        # Work bills only DevZero: its subagents keep the parent's credentials (the work token).
        # Any provider here could resolve to a personal login (the root Codex grant, the shared
        # DeepSeek and Qwen keys in the wrapper's environment).
        assertion = let
          work = config.services.imperium.hermes.profiles.work;
          d = work.delegation;
        in
          d.allowedProviders
          == []
          && lib.all (tier: tier.provider == null && tier.fallback == []) d.tiers
          && !(work.settings ? delegation);
        message = "services.imperium.hermes.profiles.work: delegation tiers must not name a provider or fallback, allowedProviders must stay empty, and settings.delegation must not be set (work bills only the DevZero token).";
      }
    ];

    # Keep the identity unavailable to the default profile's local terminal
    # until stygies is pinned. Clan can still generate the public half.
    clan.core.vars.generators.hermes-stygies-ssh.files."id_ed25519" = let
      keyOwner =
        if hasHostPin
        then "hermes"
        else "root";
    in {
      owner = lib.mkForce keyOwner;
      group = lib.mkForce keyOwner;
    };

    clan.core.vars.generators.hermes-work-claude-token = {
      prompts.token = {
        description = "Run `claude-as devzero setup-token` on your PC while signed into DevZero; paste only the token.";
        type = "hidden";
      };
      files.token = {
        secret = true;
        owner = "hermes";
        group = "hermes";
        mode = "0400";
        neededFor = "services";
      };
      runtimeInputs = [pkgs.coreutils];
      script = ''cp "$prompts/token" "$out/token"'';
    };

    programs.ssh = lib.mkIf hasHostPin {
      knownHosts.stygies = {
        hostNames = [stygies];
        publicKey = knownHosts;
      };
      # A key accepted before the pin was deployed must not override it.
      # The system block assumes ~/.ssh/config does not override it: OpenSSH
      # reads the user's config first.
      extraConfig = ''
        Host ${stygies}
          UserKnownHostsFile none
          HostKeyAlgorithms ${hostKeyAlgorithm}
      '';
    };
    services.imperium.hermes = {
      enable = true;
      extraPackages = lib.optional hasHostPin pkgs.openssh;
      profiles.coder = {
        # Hermes uses accept-new. Without a system pin, don't expose a profile
        # that could trust an unknown host or run its terminal locally on ryza.
        enable = hasHostPin;
        soul = builtins.replaceStrings ["@appProjectRule@" "@projectRoutes@"] [appProjectRule projectRoutes] (builtins.readFile ./hermes-coder-soul.md);
        # One Matrix room per project. Add the room's Internal room ID to
        # _coder-projects.nix after inviting @hermes.
        rooms = lib.mapAttrs (_: project: project.room) projects;
        # The SOUL's "Delegation" section says when to use which tier.
        delegation = {
          tiers = coderTiers;
          default = "implement";
          allowedProviders = ["anthropic" "openai-codex" "deepseek" qwenTokenPlanProvider];
          # Per call and per background pool, not overall (see the option); the SOUL also says two.
          maxConcurrentChildren = 2;
        };
        settings.terminal = sshTerminal // {cwd = "~/personal";};
        # Core /review runs through the delegation backend unless this slot is set, which would
        # put it on the `implement` tier (Sonnet). Keep it on Opus, like the coder itself.
        settings.auxiliary.review = {
          provider = "anthropic";
          model = "claude-opus-5-5";
        };
        # Kaneo uses browser PKCE. Port 28431 is outside both hosts' ephemeral
        # ranges; keep it fixed for the phalanx-to-ryza SSH tunnel.
        settings.mcp_servers.kaneo = {
          url = "https://kaneo.${self.lib.lab.domain}/api/mcp";
          auth = "oauth";
          oauth.redirect_port = 28431;
        };
      };
      profiles.work = {
        # Always enabled, pin or not. Disabling it would drop its routes, and
        # Hermes answers a room without a route as `default`, on the personal
        # login. Without the pin only the terminal goes away (see settings).
        enable = true;
        claudeOAuthTokenFile = config.clan.core.vars.generators.hermes-work-claude-token.files.token.path;
        soul = builtins.replaceStrings ["@companies@" "@repos@"] [workCompanyRows workRepoRows] (builtins.readFile ./hermes-work-soul.md);
        # One room per company, from _work-projects.nix, routed whether or not
        # its coding is enabled.
        rooms = lib.mapAttrs (_: company: company.room) workCompanies;
        delegation = {
          tiers = lib.optionals workTiersEnabled workTiers;
          default = lib.mkIf workTiersEnabled "implement";
          # Parent credentials only; asserted below.
          allowedProviders = [];
          maxConcurrentChildren = 2;
        };
        settings = {
          auth.adopt_external_logins = false;
          model = {
            inherit (workModel) provider;
            default = workModel.model;
          };
          fallback_providers = [];
          auxiliary = lib.genAttrs workAuxiliarySlots (_: workModel);
          # Hermes' ssh backend uses StrictHostKeyChecking=accept-new
          # (tools/environments/ssh.py), so without the pin the terminal must not
          # run at all. agent.disabled_toolsets is subtracted last from every
          # turn's tools (model_tools.py _select_tool_names, read per turn in
          # gateway/run_turn.py), and the file and code tools run through the
          # same backend. The key is always written: the merge never deletes,
          # so the shorter list is what lifts the block once the pin exists.
          # cronjob (toolsets.py: cronjob_manage) is always off: a cron `script:`
          # job runs locally on ryza with the work token in its environment.
          agent.disabled_toolsets =
            ["cronjob"]
            ++ lib.optionals (!hasHostPin) ["terminal" "file" "code_execution"];
          terminal = sshTerminal // {cwd = "~/work";};
          # Remote MCP servers with browser OAuth (dynamic client
          # registration), like coder's Kaneo: nothing secret in Nix, tokens
          # land in the work profile's mcp-tokens/. Fixed redirect ports, next
          # to Kaneo's 28431, for the phalanx-to-ryza SSH tunnel used by
          # `hermes -p work mcp login <name> --flow browser` (README).
          mcp_servers = {
            # Jira and Confluence: every Atlassian site the signed-in work
            # account can see. The same endpoint nautili uses on the PC.
            atlassian = {
              url = "https://mcp.atlassian.com/v1/mcp";
              auth = "oauth";
              oauth.redirect_port = 28432;
            };
            opsee = {
              url = "https://mcp.api.opsee.ai/mcp";
              auth = "oauth";
              oauth.redirect_port = 28433;
            };
          };
        };
      };
      dashboard = {
        enable = true;
        publicUrl = "https://hermes.${noosphere.domain}";
        oidc.issuer = "https://id.${noosphere.domain}";
        # The cluster nodes: Traefik's traffic arrives from whichever one its
        # pod runs on.
        allowedSources = with self.lib.hosts; [terra luna sol mars];
      };
      # @hermes on the lab homeserver, registered on cypramundi
      # (services.imperium.matrixBots there). DM it from Element.
      matrix = {
        enable = true;
        inherit (lab.matrix) homeserver serverName;
        allowedUsers = ["@kumamte:${lab.matrix.serverName}"];
      };
    };
  };
}
