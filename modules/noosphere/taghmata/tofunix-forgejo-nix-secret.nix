{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  secretsFile = "tofunix-forgejo-nix-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${secretsFile} = {
      share = true;

      files.${secretsFile}.secret = false;

      prompts.forgejo-token = {
        description = "API token for cerberus Forgejo (forge.ugalabugala.org) — Settings → Applications → Generate Token";
        type = "hidden";
        persist = false;
      };

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        forgejo_token="$(tr -d '\r\n' < "$prompts/forgejo-token")"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretsFile}" <<EOF
        forgejo_token: "$forgejo_token"
        EOF
      '';
    };
  };
}
