{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  secretsFile = "tofunix-harbor-woodpecker-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${secretsFile} = {
      share = true;

      files.${secretsFile}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
        set -euo pipefail

        # Generate a random password for the Harbor Woodpecker robot account
        password="$(openssl rand -base64 32 | tr -d '\n' | head -c 32)"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretsFile}" <<EOF
        woodpecker_password: "$password"
        EOF
      '';
    };
  };
}
