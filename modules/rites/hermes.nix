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
#   Claude plan      only through the real `claude` binary (`claude -p`) as a
#                    tool. NOT Hermes' "Anthropic OAuth" provider: that bills
#                    extra usage and is the third-party use Anthropic's terms
#                    rule out
#   API keys         `apiKeys` (the shared pi-api-keys) and `secrets`; llama-swap
#                    on phalanx as a custom OpenAI-compatible provider
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
    retireUnit = "hermes-retire-profiles";
    # Hermes 0.23.0: hermes_constants.py PROFILE_ID_RE and
    # hermes_cli/profiles.py _RESERVED_NAMES (default is not a named profile).
    profileIdPattern = "^[a-z0-9][a-z0-9_-]{0,63}$";
    reservedProfileNames = ["hermes" "default" "test" "tmp" "root" "sudo"];
    yaml = pkgs.formats.yaml {};
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
      ++ lib.mapAttrsToList (name: profile: {
        name = "profiles/${name}/config.yaml";
        path = yaml.generate "hermes-${name}-config.yaml" profile.settings;
      })
      enabledProfiles);
    configPython = pkgs.python3.withPackages (ps: [ps.ruamel-yaml]);
    profileConfigCommand = action:
      lib.escapeShellArgs [
        (lib.getExe configPython)
        ./_hermes-merge-config.py
        action
        "${home}/.hermes"
        profileConfig
      ];
    applyProfileConfig = profileConfigCommand "apply";
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
            rooms = mkOption {
              type = types.attrsOf (types.strMatching "![^[:space:]]+");
              default = {};
              example = {pilot = "!roomid:example.org";};
              description = "Matrix rooms routed to this profile by the default bot, by a short name (used in the route name). Each room is its own conversation.";
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
        cfg.profiles;

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

      system.activationScripts.hermes-config = mkIf hasEnabledProfiles {
        deps = ["users"];
        text = ''
          if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet local-fs.target; then
            ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- ${applyProfileConfig}
          fi
        '';
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

      systemd.services.hermes-gateway = {
        description = "Hermes Agent gateway";
        wantedBy = ["multi-user.target"];
        after =
          ["network-online.target" "user@${toString cfg.uid}.service"]
          ++ lib.optional (disabledProfiles != []) "${retireUnit}.service";
        requires = lib.optional (disabledProfiles != []) "${retireUnit}.service";
        wants = ["network-online.target" "user@${toString cfg.uid}.service"];
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
          hardening
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
