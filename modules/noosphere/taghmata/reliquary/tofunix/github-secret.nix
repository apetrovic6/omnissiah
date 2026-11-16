# The GitHub token tofunix uses to create mirror repositories under github.com/apetrovic6 and
# to push to them (_tofunix/projects: forgejo push mirrors over HTTPS). A fine-grained token
# for the user's own repositories, with Administration: read/write (create repos) and
# Contents: read/write (push). Prompted once; stored sops-encrypted like the other tofunix
# secrets.
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  secretsFile = "tofunix-github-secret";
in {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators.${secretsFile} = {
      share = true;

      files.${secretsFile}.secret = false;

      prompts.github-token = {
        description = "GitHub fine-grained token for github.com/apetrovic6 (Administration + Contents: read/write)";
        type = "hidden";
        persist = false;
      };

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        github_token="$(tr -d '\r\n' < "$prompts/github-token")"

        sops encrypt \
          --age "${ageKey}" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretsFile}" <<EOF
        github_token: "$github_token"
        EOF
      '';
    };
  };
}
