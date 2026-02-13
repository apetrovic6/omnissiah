{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  secretsFile = "tofunix-pocketid-secret";
  lu-user = "tofunix-pocketid-lu";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${secretsFile} = {
      share = true;

      files.${secretsFile}.secret = false;

      prompts.api-key = {
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

    clan.core.vars.generators.${lu-user} = {
      share = true;

      files.${secretsFile}.secret = false;

      prompts.username = {
        description = "Username";
        type = "line";
        persist = false;
      };

      prompts.email = {
        description = "Email";
        type = "line";
        persist = false;
      };

      prompts.first-name = {
        description = "First Name:";
        type = "line";
        persist = false;
      };

      prompts.last-name = {
        description = "Last Name:";
        type = "line";
        persist = false;
      };

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        username="$(tr -d '\r\n' < "$prompts/username")"
        email="$(tr -d '\r\n' < "$prompts/email")"
        first_name="$(tr -d '\r\n' < "$prompts/first-name")"
        last_name="$(tr -d '\r\n' < "$prompts/last-name")"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretsFile}" <<EOF
        username: "$username"
        email: "$email"
        first_name: "$first_name"
        last_name: "$last_name"
        EOF
      '';
    };
  };
}
