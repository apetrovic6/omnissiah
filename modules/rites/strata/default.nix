# Strata models served through llama-swap (docs/LLAMA_SWAP.md upstream): each
# model is one llama-swap entry that starts `strata-server` for one run config,
# so llama-swap -- not one Strata process per model -- decides what holds the
# GPU, and asking for one model unloads the other.
#
# Model preparation remains imperative (packs, GGUFs, MTP heads and .strata
# files are downloaded by hand into dataDir); Nix owns the engines, the run
# configs and the llama-swap entries. Pair with a llama-swap host config that
# binds the model directory into the service (see machines/phalanx).
{self, ...}: {
  flake.nixosModules.strata = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkEnableOption mkIf mkOption types;
    cfg = config.services.imperium.strata;
    strata = pkgs.callPackage ./_package.nix {
      src = self.inputs.strata;
    };

    # llama-swap runs as a DynamicUser with ProtectSystem=strict; its
    # StateDirectory is the only place it can write. The server writes its
    # settings beside --config, the engine its log, and the shape engines a
    # tokenizer (vocab.json) generated from the .strata file on first start.
    # All of it is regenerable, so nothing here needs persisting.
    stateDir = "/var/lib/llama-swap/strata";
    engineExe = name: "${strata.engine}/libexec/strata/${name}";

    # One llama-swap entry: link the store config into the writable state dir,
    # then exec the server on llama-swap's port. `exec` so llama-swap's SIGTERM
    # reaches the server, which stops its engine and frees the GPU.
    mkEntry = {
      name,
      runConfig,
      ttl,
    }: let
      configFile = pkgs.writeText "${name}.json" (builtins.toJSON runConfig);
      launcher = pkgs.writeShellScript "strata-${name}" ''
        set -eu
        mkdir -p ${stateDir}/${name}/tokenizer ${stateDir}/${name}/conv-cache
        # Neither HOME nor XDG_* exist for a DynamicUser; keep anything the
        # server writes under its own state.
        export HOME=${stateDir} XDG_CONFIG_HOME=${stateDir}/.config XDG_CACHE_HOME=${stateDir}/.cache
        ln -sfn ${configFile} ${stateDir}/${name}.json
        exec ${lib.getExe strata.server} --engine strata --config ${stateDir}/${name}.json --port "$1"
      '';
    in {
      inherit ttl;
      cmd = "${launcher} \${PORT}";
      # /health answers only once the model is loaded.
      checkEndpoint = "/health";
    };

    # ---- Qwen3.8-Flash-Next (ISTA-DASLab packs), the `strata` engine ----
    q = cfg.qwen;
    tag = lib.optionalString (q.family == "coder") "coder-" + q.quant;
    shard = i: "${cfg.dataDir}/models/${tag}/Qwen3.8-Flash-Next-GSQ-RCO-${q.quant}-0000${toString i}-of-00002.gguf";
    pack = "${cfg.dataDir}/packs/${lib.toLower tag}";
    qwenConfig = {
      exe = engineExe "strata";
      args =
        [
          "--pack"
          pack
          "--native"
          (shard 1)
          "--ple-gguf"
          (shard 2)
          "--expert-profile"
          "${strata.src}/terminal/data/expert-profile${lib.optionalString (q.family == "coder") "-coder"}.bin"
          "--expert-cache"
          "auto"
          "--prefill"
          q.prefill
          "--spec"
          (toString q.specTokens)
          "--spec-min-p"
          "0.5"
          "--mtp"
          "${cfg.dataDir}/mtp/rt"
          "--max-context"
          (toString q.maxContext)
          "--kv"
          q.kvType
          "--kv-resident"
          (toString q.kvResident)
        ]
        ++ q.extraArgs;
      # The server copies this into the engine's environment.
      env = q.engineEnv;
      cwd = "${stateDir}/${q.modelName}";
      tokenizer = "${pack}/tokenizer";
      model_name = q.modelName;
      log = "${stateDir}/${q.modelName}/engine.log";
      lib_dirs = [];
      inherit (cfg) gpu;
      gpus_asked = true;
    };

    # ---- Inkling 2 Mini (.strata pack), the `strata-inkling` shape engine ----
    ink = cfg.inkling;
    inkDir = "${cfg.dataDir}/models/inkling-2-mini";
    inklingConfig = {
      exe = engineExe "strata-inkling";
      # serve/inkling_kind.py routes by this.
      arch = "inkling2_loop";
      args =
        [
          "--native"
          "${inkDir}/Inkling-2-Mini-${ink.pack}.strata"
          "--max-context"
          (toString ink.maxContext)
        ]
        ++ lib.optionals ink.vision ["--vision" "${inkDir}/Inkling-2-Mini-Vision.strata"]
        ++ lib.optionals (ink.drafting == "dspark") ["--dspark" "${inkDir}/mtp.safetensors"];
      inherit (ink) drafting;
      cwd = "${stateDir}/${ink.modelName}";
      # Writable: the server generates vocab.json here from the pack's
      # manifest (serve/server.py _ensure_shape_tokenizer).
      tokenizer = "${stateDir}/${ink.modelName}/tokenizer";
      model_name = ink.modelName;
      log = "${stateDir}/${ink.modelName}/engine.log";
      lib_dirs = [];
      inherit (cfg) gpu;
      gpus_asked = true;
    };

    # ---- Tencent Hy4-Flash (.strata pack + Engram), the `strata-hy4` engine ----
    hy = cfg.hy4;
    hyDir = "${cfg.dataDir}/models/hy4-flash";
    hy4Config = {
      exe = engineExe "strata-hy4";
      # serve/hy4_kind.py routes by this.
      arch = "hy4flash";
      args =
        [
          "--native"
          "${hyDir}/Hy4-Flash-${hy.pack}.strata"
          "--engram"
          "${hyDir}/Hy4-Flash-Engram-Q8.strata"
          "--max-context"
          (toString hy.maxContext)
          # Keep the KV of a prompt that extends the last one.
          "--session-reuse"
          "1"
        ]
        ++ lib.optionals hy.vision ["--vision" "${hyDir}/Hy4-Flash-Vision.strata"]
        # Without it the engine cannot rewind: a harness that drops the old
        # turn's thinking makes the next prompt a non-extension, and every turn
        # re-reads the whole conversation (measured 2026-11-28: 17,007 of
        # 17,007 tokens re-read; with the cache, 23).
        ++ lib.optionals (hy.conversationCacheGiB > 0) [
          "--conversation-cache-dir"
          "${stateDir}/${hy.modelName}/conv-cache"
          "--conversation-cache-gib"
          (toString hy.conversationCacheGiB)
        ];
      cwd = "${stateDir}/${hy.modelName}";
      tokenizer = "${stateDir}/${hy.modelName}/tokenizer";
      model_name = hy.modelName;
      log = "${stateDir}/${hy.modelName}/engine.log";
      lib_dirs = [];
      inherit (cfg) gpu;
      gpus_asked = true;
    };
  in {
    options.services.imperium.strata = {
      enable = mkEnableOption "Strata models as llama-swap entries";
      dataDir = mkOption {
        type = types.str;
        description = ''
          Model data populated by hand (packs, models, mtp), as the llama-swap
          service sees it -- i.e. under its bind mount, not the host path.
        '';
      };
      gpu = mkOption {
        type = types.ints.unsigned;
        default = 0;
        description = "Physical NVIDIA GPU index. CUDA build targets come from nixpkgs.config.cudaCapabilities.";
      };

      qwen = {
        enable = mkEnableOption "Qwen3.8-Flash-Next on the strata engine" // {default = true;};
        family = mkOption {
          type = types.enum ["qwen" "coder"];
          default = "qwen";
          description = "Original Flash-Next or its expert-pruned GSQ-RCO Coder variant.";
        };
        quant = mkOption {
          type = types.enum ["Q2_0" "IQ2_XS" "IQ3_XXS" "IQ3_S" "IQ1_M"];
          default =
            if q.family == "coder"
            then "IQ1_M"
            else "IQ3_XXS";
          description = "Prepared ISTA-DASLab quantization; Coder requires IQ1_M.";
        };
        modelName = mkOption {
          type = types.str;
          default = "qwen3.8-flash-next-${lib.toLower tag}";
          description = "Model ID, both the llama-swap entry and the API's; clients must use this name.";
        };
        maxContext = mkOption {
          type = types.ints.positive;
          default = 32768;
          description = "Maximum token context allocated by the engine.";
        };
        kvResident = mkOption {
          type = types.ints.positive;
          default = lib.min q.maxContext 32768;
          description = "Token count of the GPU-resident KV window.";
        };
        kvType = mkOption {
          type = types.enum ["int8" "q4_0" "k8v4"];
          default = "int8";
          description = "Engine KV cache precision.";
        };
        prefill = mkOption {
          type = types.str;
          default = "auto";
          description = "Engine prompt chunk size (auto or an explicit token count).";
        };
        specTokens = mkOption {
          type = types.ints.unsigned;
          default = 4;
          description = "Number of speculative MTP draft tokens; zero disables speculation.";
        };
        ttl = mkOption {
          type = types.ints.unsigned;
          default = 3600;
          description = "Idle seconds before llama-swap unloads the model.";
        };
        extraArgs = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional engine arguments for host-specific tuning.";
        };
        engineEnv = mkOption {
          type = types.attrsOf types.str;
          default = {};
          example = {STRATA_ROUTE_TAIL_SKIP = "7";};
          description = "Environment variables (STRATA_* switches) passed to the engine process.";
        };
      };

      inkling = {
        enable = mkEnableOption "Inkling 2 Mini on the strata-inkling engine";
        pack = mkOption {
          type = types.enum ["SQ-10" "SQ-15" "SQ-20"];
          default = "SQ-15";
          description = "Strata's own .strata build, in dataDir/models/inkling-2-mini.";
        };
        modelName = mkOption {
          type = types.str;
          default = "inkling-2-mini-${lib.toLower ink.pack}";
          description = "Model ID, both the llama-swap entry and the API's.";
        };
        maxContext = mkOption {
          type = types.ints.positive;
          default = 131072;
          description = "Maximum token context; the engine offloads global KV to host RAM when VRAM is short.";
        };
        vision = mkOption {
          type = types.bool;
          default = true;
          description = "Load Inkling-2-Mini-Vision.strata for image input.";
        };
        drafting = mkOption {
          type = types.enum ["off" "dspark"];
          default = "off";
          description = "DSpark speculative decoding (needs mtp.safetensors).";
        };
        ttl = mkOption {
          type = types.ints.unsigned;
          default = 900;
          description = "Idle seconds before llama-swap unloads the model.";
        };
      };

      hy4 = {
        enable = mkEnableOption "Tencent Hy4-Flash on the strata-hy4 engine";
        pack = mkOption {
          type = types.enum ["SQ-64" "SQ-96" "SQ-128"];
          default = "SQ-64";
          description = "Strata's own .strata build, in dataDir/models/hy4-flash beside the shared Engram file.";
        };
        modelName = mkOption {
          type = types.str;
          default = "hy4-flash-${lib.toLower hy.pack}";
          description = "Model ID, both the llama-swap entry and the API's.";
        };
        maxContext = mkOption {
          type = types.ints.positive;
          default = 131072;
          description = "Maximum token context (upstream's default is 128K).";
        };
        vision = mkOption {
          type = types.bool;
          default = true;
          description = "Load Hy4-Flash-Vision.strata for image input.";
        };
        conversationCacheGiB = mkOption {
          type = types.ints.unsigned;
          default = 16;
          description = ''
            Size of the on-disk conversation cache in the state dir; 0 turns it
            off. Needed for KV reuse whenever a client rewrites history.
          '';
        };
        ttl = mkOption {
          type = types.ints.unsigned;
          default = 900;
          description = "Idle seconds before llama-swap unloads the model.";
        };
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = (q.family == "coder") == (q.quant == "IQ1_M");
          message = "Strata: IQ1_M is exclusive to the Coder family; Coder requires IQ1_M.";
        }
        {
          assertion = q.kvResident <= q.maxContext;
          message = "Strata: kvResident must not exceed maxContext.";
        }
        {
          assertion = config.services.llama-swap.enable;
          message = "Strata: models are served through llama-swap; enable services.llama-swap.";
        }
      ];

      services.llama-swap.settings.models =
        lib.optionalAttrs q.enable {
          ${q.modelName} = mkEntry {
            name = q.modelName;
            runConfig = qwenConfig;
            inherit (q) ttl;
          };
        }
        // lib.optionalAttrs ink.enable {
          ${ink.modelName} = mkEntry {
            name = ink.modelName;
            runConfig = inklingConfig;
            inherit (ink) ttl;
          };
        }
        // lib.optionalAttrs hy.enable {
          ${hy.modelName} = mkEntry {
            name = hy.modelName;
            runConfig = hy4Config;
            inherit (hy) ttl;
          };
        };

      systemd.services.llama-swap.serviceConfig =
        {StateDirectory = "llama-swap";}
        # strata-hy4 mlocks its ~56GB RAM expert store ("mlock=yes" in its
        # log); the service default of 8MB would refuse that.
        // lib.optionalAttrs hy.enable {LimitMEMLOCK = "infinity";};
    };
  };
}
