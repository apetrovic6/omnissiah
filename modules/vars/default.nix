{self, ...}: {
  flake.nixosModules.vars = {
    config,
    lib,
    pkgs,
    ...
  }: {
    # Optional: choose where secrets go (defaults to "sops")
    clan.core.vars.settings.secretStore = "sops";

    clan.core.vars.generators.attic-pull-token = {
      share = true;

      files.token = {
        # secret = true is the default, so this is actually optional
        secret = true;
        # You can also set owner/group/mode if a service user needs it
        owner = "apetrovic";
        # group = "some-service-group";
        mode = "0400";
      };

      files.attic-substituter = {
        secret = true;
        owner = "apetrovic";
      };
    };

    # API keys for pi (and omp) coding agents. Shared across all machines so
    # the key is generated once and sops-encrypted in the clan secret store.
    #
    # After generating with:
    #   clan vars generate --generator pi-api-keys <machine>
    # the decrypted secret lands at:
    #   /run/secrets/pi-api-keys/qwen-api-key   (owner: apetrovic, mode: 0400)
    #
    # The pi wrapper (magos) reads this file at startup and exports it as
    # $QWEN_TOKEN_PLAN_API_KEY, which pi's models.json references via ${...}
    # interpolation. Add more files below for other providers (anthropic,
    # openai, etc.) and mirror them in the wrapper's secret-sourcing loop.
    clan.core.vars.generators.pi-api-keys = {
      share = true;

      files."qwen-api-key" = {
        secret = true;
        owner = "apetrovic";
        mode = "0400";
      };

      # Add more provider keys as needed:
      # files."anthropic-api-key" = {
      #   secret = true;
      #   owner = "apetrovic";
      #   mode = "0400";
      # };
      # files."openai-api-key" = {
      #   secret = true;
      #   owner = "apetrovic";
      #   mode = "0400";
      # };

      prompts."qwen-api-key" = {
        description = "Qwen API key (QWEN_TOKEN_PLAN_API_KEY) — get one at https://bailian.console.aliyun.com/";
        type = "hidden";
        persist = true;
      };

      runtimeInputs = [pkgs.coreutils];
      script = ''
        cp "$prompts/qwen-api-key" "$out/qwen-api-key"
      '';
    };
  };
}
