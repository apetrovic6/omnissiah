{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
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
      glance-secrets = {
        namespace = "glance";
        prompts.github-token.description = "GitHub fine-grained PAT for Glance releases widget (public repo read only)";
        setup = ''
          if [ -z "$github_token" ]; then
            echo "ERROR: github-token prompt was empty; refusing to write a useless secret" >&2
            exit 1
          fi
        '';
        # The Secret key must be exactly GLANCE_GITHUB_TOKEN: the Deployment
        # consumes it via envFrom, so the key becomes the environment variable
        # name that home.yml interpolates as ''${GLANCE_GITHUB_TOKEN}.
        data.GLANCE_GITHUB_TOKEN = "$github_token";
      };
    };
  };
}
