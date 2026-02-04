{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  secretsFile = "tofunix-harbor-secrets";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${secretsFile} = {
      share = true;

      files.${secretsFile}.secret = false;

      prompts.harbor-username = {
        description = "Harbor robot account username (e.g., robot$opentofu)";
        type = "line";
        persist = false;
      };

      prompts.harbor-password = {
        description = "Harbor robot account password";
        type = "hidden";
        persist = false;
      };

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        harbor_username="$(tr -d '\r\n' < "$prompts/harbor-username")"
        harbor_password="$(tr -d '\r\n' < "$prompts/harbor-password")"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretsFile}" <<EOF
        harbor_username: "$harbor_username"
        harbor_password: "$harbor_password"
        EOF
      '';
    };
  };
}
