{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  glanceSecrets = "glance-secrets";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    # GitHub API token for the Glance `releases` widget.
    #
    # The widget polls api.github.com for ~39 repositories per refresh. The
    # unauthenticated rate limit is 60 requests/hour/IP, and a partial failure
    # makes Glance reschedule an *early* retry (now + retries^2 minutes), which
    # burns the quota further and cascades into "could not get N releases".
    # A token raises the limit to 5000/hour.
    #
    # Use a fine-grained PAT with no repos explicitly granted — public-repo
    # read is all Glance needs.
    clan.core.vars.generators.${glanceSecrets} = {
      share = true;

      prompts.github-token = {
        description = "GitHub fine-grained PAT for Glance releases widget (public repo read only)";
        type = "hidden";
        persist = false;
      };

      # The SopsSecret document is already age-encrypted by sops itself, so the
      # var file is not marked secret (same convention as the other generators).
      files.${glanceSecrets}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.jq];

      script = ''
        set -euo pipefail

        github_token="$(tr -d '\r\n' < "$prompts/github-token")"

        if [ -z "$github_token" ]; then
          echo "ERROR: github-token prompt was empty; refusing to write a useless secret" >&2
          exit 1
        fi

        # The Secret key must be exactly GLANCE_GITHUB_TOKEN: the Deployment
        # consumes it via envFrom, so the key becomes the environment variable
        # name that home.yml interpolates as ''${GLANCE_GITHUB_TOKEN}.
        jq -n \
          --arg github_token "$github_token" \
          '{
            apiVersion: "isindir.github.com/v1alpha3",
            kind: "SopsSecret",
            metadata: {
              name: "glance-secrets",
              namespace: "glance"
            },
            spec: {
              secretTemplates: [{
                name: "glance-secrets",
                type: "Opaque",
                stringData: {
                  "GLANCE_GITHUB_TOKEN": $github_token
                }
              }]
            }
          }' | sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type json --output-type yaml \
          /dev/stdin > "$out/${glanceSecrets}"
      '';
    };
  };
}
