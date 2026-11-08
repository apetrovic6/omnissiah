# A GitHub token for Nix's own fetches, so `nix flake update` (and any other
# fetch of a github: input) authenticates instead of sharing the anonymous
# 60-requests-an-hour limit and dying on HTTP 403/429 halfway through.
#
# The token needs NO permissions: a fine-grained personal access token with
# "Public repositories (read-only)" and nothing else is enough for every
# github: input in this flake, and raises the limit to 5000 an hour. Create one
# at https://github.com/settings/personal-access-tokens/new, then
#   clan vars generate <machine> --generator github-token
# (shared, so one prompt covers every machine that enables this module).
#
# The token never enters the Nix store or the world-readable /etc/nix/nix.conf:
# nix.conf only carries an `!include` of the decrypted secret, which holds the
# `access-tokens = github.com=<token>` line. `!include` (not `include`) skips a
# missing file silently, so a machine whose secret is not deployed yet still
# has a working Nix -- just an anonymous one.
#
# Owned by apetrovic: flake inputs are fetched by the client process (the nix
# command run as the user), not by the daemon, so the user has to be able to
# read it. Root reads it regardless.
{...}: {
  flake.nixosModules.github-token = {
    config,
    pkgs,
    ...
  }: let
    generator = config.clan.core.vars.generators.github-token;
  in {
    clan.core.vars.generators.github-token = {
      share = true;

      prompts.token = {
        description = "GitHub fine-grained personal access token for Nix fetches (no permissions beyond public read-only)";
        type = "hidden";
        persist = true;
      };

      files."access-tokens.conf" = {
        secret = true;
        owner = "apetrovic";
        mode = "0400";
      };

      runtimeInputs = [pkgs.coreutils];

      script = ''
        set -euo pipefail

        token="$(tr -d '[:space:]' < "$prompts/token")"

        # Fine-grained (github_pat_), classic (ghp_) and OAuth (gho_) tokens.
        # Anything else is a mis-paste, and a bad token makes every github:
        # fetch fail with 401 rather than fall back to anonymous.
        case "$token" in
          github_pat_* | ghp_* | gho_*) ;;
          *)
            echo "github-token: expected a GitHub token (github_pat_…, ghp_… or gho_…)" >&2
            exit 1
            ;;
        esac

        printf 'access-tokens = github.com=%s\n' "$token" > "$out/access-tokens.conf"
      '';
    };

    nix.extraOptions = ''
      !include ${generator.files."access-tokens.conf".path}
    '';
  };
}
