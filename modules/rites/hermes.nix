# Hermes Agent (Nous Research): an always-on agent. The gateway runs its
# cron jobs and any messaging platform whose token is in the env file;
# with none set (the default here) it is reached from its CLI/TUI over SSH.
# Packaged in llm-agents (numtide/llm-agents.nix, reached through magos),
# with Claude Code and Codex beside it as tools.
#
# How the model access splits (see the 2026-11-22 notes in memory):
#   ChatGPT plan     Hermes' own "OpenAI Codex" provider, a device-code login
#                    stored in ~/.hermes/auth.json
#   Claude plan      only through the real `claude` binary (`claude -p`) as a
#                    tool. NOT Hermes' "Anthropic OAuth" provider: that bills
#                    extra usage and is the third-party use Anthropic's terms
#                    rule out
#   API keys         `apiKeys` (the shared pi-api-keys) and `secrets`; llama-swap
#                    on phalanx as a custom OpenAI-compatible provider
#
# Everything Hermes learns lives in its home: ~/.hermes (config.yaml,
# MEMORY.md, USER.md, skills, sessions, auth.json), ~/.claude and ~/.codex.
# It edits those itself, so none of it is declarative.
#
# One-time setup, as the hermes user (`sudo -u hermes -i`):
#   hermes model              pick providers, log in to ChatGPT (device code)
#   claude                    /login with the Claude account
#   codex login --device-auth only if the agent should drive codex directly
#   hermes                    talk to it (the TUI); sessions and memory are
#                             shared with the gateway
#
# Isolation: the hermes user has no sudo, no SSH keys into the clan and no
# access to the CI microVM. Its cron/Kanban workers start through
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
      });
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
    sessionEnv = {
      HOME = home;
      USER = user;
      LOGNAME = user;
      # For `systemd-run --user` from the gateway.
      XDG_RUNTIME_DIR = "/run/user/${toString cfg.uid}";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/${toString cfg.uid}/bus";
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
  in {
    imports = [self.nixosModules.pi-api-keys];

    options.services.imperium.hermes = {
      enable = mkEnableOption "the Hermes Agent gateway";
      package = mkOption {
        type = types.package;
        default = llm.hermes-agent;
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
      ];

      systemd.services.hermes-gateway = {
        description = "Hermes Agent gateway";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target" "user@${toString cfg.uid}.service"];
        wants = ["network-online.target" "user@${toString cfg.uid}.service"];
        path = tools;
        environment = sessionEnv;
        serviceConfig =
          hardening
          // {
            ExecStart = "${hermes}/bin/hermes gateway run";
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
          hardening
          // {
            ExecStart = "${hermes}/bin/hermes dashboard --host 0.0.0.0 --port ${toString cfg.dashboard.port}";
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
