{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  secretsFile = "tofunix-pocketid-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${secretsFile} = {
      share = true;

      files.${secretsFile}.secret = false;

      prompts.api-key= {
        description = "PocketId API token (Settings -> Administration -> API Keys)";
        type = "hidden";
        persist = false;
      };

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        api_key="$(tr -d '\r\n' < "$prompts/api-key")"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretsFile}" <<EOF
        api_key: "$api_key"
        EOF
      '';
    };
  };
}
