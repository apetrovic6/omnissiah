{
  self,
  config,
  pkgs,
  ...
}: {
  clan.core.vars.generators.forgejo-runner-token = {
    files."token" = {
      secret = true;
      mode = "0400";
    };
    prompts.token = {
      description = "Forgejo Actions runner registration token (from Forgejo -> Actions -> Runners)";
      type = "hidden";
      persist = true;
    };
    runtimeInputs = [pkgs.coreutils];
    script = ''
      set -eu

      token="$(cat "$prompts/token")"

      cat > "$out/token" <<EOF
      TOKEN=$token
      EOF
    '';
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.cerberus = {
      enable = true;
      name = "cerberus-nix";
      url = "http://localhost:9000";
      tokenFile = config.clan.core.vars.generators.forgejo-runner-token.files."token".path;
      # Jobs `runs-on: nix` run directly on this host (no container), so they can
      # use the host's Nix store as a build cache.
      labels = ["nix:host"];
      # PATH available to host-executed jobs: the workflow needs node (for
      # actions/checkout), devenv (the build), nix (devenv shells out to it),
      # and the usual coreutils/git/tar.
      hostPackages =
        [config.nix.package]
        ++ (with pkgs; [
          bash
          coreutils
          gnutar
          gzip
          git
          nodejs
          devenv
          cacert
        ]);
    };
  };
}
