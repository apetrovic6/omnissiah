# One generated secret per product (./_products.nix) for its Harbor robot account. tofunix sets
# it on the robot and on the product repo's HARBOR_PASSWORD action secret, so no human ever
# copies it (see the Harbor OIDC hand-copied-secret incident).
#
# Same shape as tofunix-harbor-woodpecker-secret: a sops-encrypted YAML file that the tofunix
# sops provider decrypts, so the var file itself is not a clan secret.
{
  config,
  lib,
  ...
}: let
  ageKey = config.noosphere.agePublicKey;
  products = import ./_products.nix;
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators = lib.mapAttrs' (name: _: let
      secretsFile = "tofunix-harbor-robot-${name}";
    in
      lib.nameValuePair secretsFile {
        share = true;

        files.${secretsFile}.secret = false;

        runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.sops pkgs.openssl];

        script = ''
          set -euo pipefail

          # Harbor refuses a robot secret without an upper-case letter, a lower-case letter and
          # a digit, so draw until one has all three.
          while :; do
            password="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
            if printf '%s' "$password" | grep -q '[A-Z]' \
              && printf '%s' "$password" | grep -q '[a-z]' \
              && printf '%s' "$password" | grep -q '[0-9]'; then
              break
            fi
          done

          sops encrypt \
            --age "${ageKey}" \
            --input-type yaml --output-type yaml \
            /dev/stdin > "$out/${secretsFile}" <<EOF
          robot_secret: "$password"
          EOF
        '';
      })
    products;
  };
}
