# Credentials for the shared sccache compilation cache: the `sccache` bucket on
# the `garage-main` Garage cluster.
#
# The cache serves cargo builds that run OUTSIDE the Nix sandbox -- the user's
# workstations (and the agent worktrees on them) and the Forgejo runners' host
# steps. Nix builds stay as they are, cached by ncps; nothing here touches them,
# and generated products (rust-app-template) deliberately do not depend on this
# Garage: their devenv.nix knows nothing about sccache.
#
# Same inverted flow as reliquary/{kaneo,memos}, but it lives here
# rather than under taghmata/reliquary because the machines that need the
# credentials are not all cluster nodes: the workstations use it too.
# Every machine that enables this module gets the generator, so the clan var is
# deployed to all of them. The key pair is minted by the var and IMPORTED into
# Garage via `GarageKey.spec.importKey.secretRef` (see
# nixidy/apps/datavault/garage-operator/_cluster-main/default.nix), so the machines
# and Garage are fed from one source and nothing is copied by hand.
#
# Two outputs:
#   - sccache-garage-key  (non-secret) sops-encrypted SopsSecret, read into the
#                         garage-operator app with builtins.readFile
#   - credentials         (secret)     AWS shared-credentials-format file
#                         ([default] profile), which is what sccache 0.19's S3
#                         backend (opendal -> reqsign) reads through
#                         AWS_SHARED_CREDENTIALS_FILE. Root-owned by default:
#                         the runner services read it as root through systemd
#                         LoadCredential (their DynamicUser cannot own files).
#                         stc/workstation.nix overrides the owner to apetrovic
#                         so the user's sccache server can read it directly.
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  domain = config.noosphere.domain;
  generatorName = "sccache-garage-key";
  # Name of the SopsSecret-backed Secret the operator imports FROM. Deliberately
  # not "sccache": that is the GarageKey's own name, and the operator writes its
  # own Secret under that name.
  importSecret = "sccache-s3-import";
in {
  flake.nixosModules.sccache = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.imperium.sccache;
  in {
    options.services.imperium.sccache = {
      enable = lib.mkEnableOption "credentials for the shared sccache bucket on garage-main";

      # Read-only knobs: every consumer (forgejo-runner.nix, the workstation
      # home-manager config) takes its values from here so the machines and the
      # bucket cannot drift apart.
      bucket = lib.mkOption {
        type = lib.types.str;
        default = "sccache";
        readOnly = true;
        description = "GarageBucket name on garage-main that holds the cache objects.";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "https://s3.main.garage.${domain}";
        readOnly = true;
        description = ''
          S3 endpoint (LAN VIP through Traefik; LAN/VPN only, no Pangolin route).
          The scheme is part of the value: sccache's endpoint resolver defaults a
          scheme-less endpoint to HTTP.
        '';
      };
      region = lib.mkOption {
        type = lib.types.str;
        default = "main";
        readOnly = true;
        description = "S3 region; garage-main's s3Api.region.";
      };

      # The only `sccache` binary consumers should ever invoke: a wrapper
      # around pkgs.sccache that scrubs the two classes of environment
      # pollution that break the shared cache (per-checkout CARGO_* in every
      # cache key; ambient AWS_* beating the credentials file). Defined once
      # here so the runners (forgejo-runner.nix) and the workstations
      # (stc/workstation.nix, users/apetrovic/home-configuration.nix) cannot
      # drift apart, and shipped under the name `sccache` so that no plain
      # invocation on any PATH can bypass it.
      wrapper = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = import ./_sccache-wrapper.nix {
          inherit lib pkgs;
          credentialsFile = config.clan.core.vars.generators.${generatorName}.files.credentials.path;
        };
        defaultText = lib.literalExpression ''
          writeShellScriptBin "sccache" -- unsets CARGO_INSTALL_ROOT and the
          ambient AWS_* credential vars, defaults AWS_SHARED_CREDENTIALS_FILE
          to the machine's clan var file, runs the compiler directly when the
          sccache server cannot start (Garage unreachable), execs pkgs.sccache
        '';
        description = ''
          Credentialed, cache-key-scrubbing sccache wrapper. Use this
          everywhere instead of the bare binary: as RUSTC_WRAPPER and as the
          `sccache` on PATH.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      clan.core.vars.generators.${generatorName} = import ./_sccache-garage-key.nix {
        inherit lib pkgs ageKey generatorName importSecret;
      };
    };
  };
}
