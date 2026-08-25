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
        ++ [
          # Drives the Dagger pipeline in the `fishing` repo. Must match the
          # engine container version in ./dagger.nix (v0.21.8) — the SDK
          # refuses to start a session against a different engine.
          self.inputs.dagger-cli.packages.${pkgs.stdenv.hostPlatform.system}.dagger
        ]
        ++ (with pkgs; [
          bash
          coreutils
          gnutar
          gzip
          git
          nodejs
          devenv
          cacert
          # Builds the pipeline driver itself (`cargo run -p ci`). The pipeline
          # then does all real work inside engine containers, so only a
          # host-side toolchain new enough for edition 2024 is needed here.
          cargo
          rustc
          # cargo needs a linker for build scripts (proc-macro2, libc, ...).
          # Without it every build script fails with `linker 'cc' not found`.
          # This wrapper provides cc/gcc/ld.
          stdenv.cc
        ]);
    };
  };
}
