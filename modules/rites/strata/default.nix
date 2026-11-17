# CUDA inference for the original and expert-pruned Coder Flash-Next packs.
# Model preparation remains imperative; Nix owns the engine, config and service.
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
      llamaCpp = self.inputs.strata-llama-cpp;
    };
    home = config.users.users.${cfg.user}.home;
    stateDir = "${home}/.local/state/strata";
    tag = lib.optionalString (cfg.family == "coder") "coder-" + cfg.quant;
    configName = "strata-${lib.toLower tag}";
    shard = i: "${cfg.dataDir}/models/${tag}/Qwen3.8-Flash-Next-GSQ-RCO-${cfg.quant}-0000${toString i}-of-00002.gguf";
    engineConfig = pkgs.writeText "${configName}.json" (builtins.toJSON {
      exe = "${strata.engine}/libexec/strata/strata";
      args =
        [
          "--pack"
          cfg.pack
          "--native"
          cfg.native
          "--ple-gguf"
          cfg.ple
          "--expert-profile"
          cfg.expertProfile
          "--expert-cache"
          "auto"
          "--prefill"
          cfg.prefill
          "--spec"
          (toString cfg.specTokens)
          "--spec-min-p"
          "0.5"
          "--mtp"
          cfg.mtp
          "--max-context"
          (toString cfg.maxContext)
          "--kv"
          cfg.kvType
          "--kv-resident"
          (toString cfg.kvResident)
        ]
        ++ cfg.extraArgs;
      cwd = stateDir;
      tokenizer = "${cfg.pack}/tokenizer";
      model_name = cfg.modelName;
      log = "${stateDir}/${configName}.log";
      lib_dirs = [];
      inherit (cfg) port gpu;
      gpus_asked = true;
    });
  in {
    options.services.imperium.strata = {
      enable = mkEnableOption "the Strata CUDA inference user service";
      user = mkOption {
        type = types.str;
        description = "Existing user whose home contains the model data and service state.";
      };
      family = mkOption {
        type = types.enum ["qwen" "coder"];
        default = "qwen";
        description = "Original Flash-Next or its expert-pruned GSQ-RCO Coder variant.";
      };
      quant = mkOption {
        type = types.enum ["Q2_0" "IQ2_XS" "IQ3_XXS" "IQ3_S" "IQ1_M"];
        default =
          if cfg.family == "coder"
          then "IQ1_M"
          else "IQ3_XXS";
        description = "Prepared ISTA-DASLab quantization; Coder requires IQ1_M.";
      };
      modelName = mkOption {
        type = types.str;
        default = "qwen3.8-flash-next-${lib.toLower tag}";
        description = "Model ID advertised by the API; clients must use this name.";
      };
      dataDir = mkOption {
        type = types.str;
        default = "${home}/models/strata-data";
        description = "Persistent directory populated by upstream model preparation, not by Nix.";
      };
      pack = mkOption {
        type = types.str;
        default = "${cfg.dataDir}/packs/${lib.toLower tag}";
        description = "Prepared engine pack directory, including its tokenizer subdirectory.";
      };
      native = mkOption {
        type = types.str;
        default = shard 1;
        description = "First GGUF shard containing the native model weights.";
      };
      ple = mkOption {
        type = types.str;
        default = shard 2;
        description = "GGUF shard containing the n-gram lookup table.";
      };
      mtp = mkOption {
        type = types.str;
        default = "${cfg.dataDir}/mtp/rt";
        description = "Prepared MTP draft head directory.";
      };
      expertProfile = mkOption {
        type = types.str;
        default = "${strata.src}/data/expert-profile${lib.optionalString (cfg.family == "coder") "-coder"}.bin";
        description = "Expert usage profile matching the model's expert count.";
      };
      gpu = mkOption {
        type = types.ints.unsigned;
        default = 0;
        description = "Physical NVIDIA GPU index. CUDA build targets come from nixpkgs.config.cudaCapabilities.";
      };
      port = mkOption {
        type = types.port;
        default = 8000;
        description = "Local API port; no firewall port is opened.";
      };
      maxContext = mkOption {
        type = types.ints.positive;
        default = 32768;
        description = "Maximum token context allocated by the engine.";
      };
      kvResident = mkOption {
        type = types.ints.positive;
        default = lib.min cfg.maxContext 32768;
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
      lazy = mkOption {
        type = types.bool;
        default = true;
        description = "Load the engine only when an inference request arrives.";
      };
      idleUnload = mkOption {
        type = types.ints.unsigned;
        default = 3600;
        description = "Idle seconds before unloading the engine; zero disables idle unloading.";
      };
      minFreeVramMiB = mkOption {
        type = types.ints.unsigned;
        default = 2048;
        description = "Minimum free GPU memory before accepting a cold model load.";
      };
      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Additional engine arguments for host-specific tuning.";
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = (cfg.family == "coder") == (cfg.quant == "IQ1_M");
          message = "Strata: IQ1_M is exclusive to the Coder family; Coder requires IQ1_M.";
        }
        {
          assertion = cfg.kvResident <= cfg.maxContext;
          message = "Strata: kvResident must not exceed maxContext.";
        }
      ];

      systemd.user.services.strata = {
        description = "Strata inference engine (${cfg.modelName})";
        wantedBy = ["default.target"];
        # NixOS user units are visible to every account, but only this user
        # owns these model files and should start the listener.
        unitConfig.ConditionUser = cfg.user;
        path = [config.hardware.nvidia.package.bin];
        serviceConfig = {
          Type = "simple";
          StateDirectory = "strata";
          WorkingDirectory = stateDir;
          # The server writes settings beside --config. Keep that directory
          # writable while the generated config itself stays in the store.
          ExecStartPre = lib.escapeShellArgs [
            "${pkgs.coreutils}/bin/ln"
            "-sfn"
            engineConfig
            "${stateDir}/${configName}.json"
          ];
          ExecStart = lib.escapeShellArgs ([
              (lib.getExe strata.server)
              "--engine"
              "strata"
              "--config"
              "${stateDir}/${configName}.json"
              "--port"
              (toString cfg.port)
            ]
            ++ lib.optional cfg.lazy "--lazy"
            ++ [
              "--idle-unload"
              (toString cfg.idleUnload)
              "--min-free-vram-mib"
              (toString cfg.minFreeVramMiB)
            ]);
          Restart = "on-failure";
          RestartSec = 10;
        };
      };
    };
  };
}
