# Forgejo Actions runners, one per machine, each registered with every Forgejo
# it lists in `forges`.
#
# Registration is offline and needs no human-copied token. Each machine/forge
# pair gets a clan var holding a random 40-hex secret. The runner connects with
# it, and the forge learns it via `forgejo-cli actions register`, which
# `nix run .#forgejo-runner-register -- <machine>` runs against every forge
# that machine lists. Both sides derive the runner uuid from the secret the
# same way: the ASCII bytes of its first 16 characters, NOT hex-decoded
# (forgejo-runner create-runner-file.go uuidFromSecret, Forgejo
# models/actions/forgejo.go). The generator below has to match that exactly.
#
# Adding a runner:
#   1. services.imperium.forgejoRunner.enable = true on the machine
#   2. clan vars generate <machine>
#   3. nix run .#forgejo-runner-register -- <machine>   (idempotent)
#   4. clan machines update <machine>
#
# EVERY RUNNER CARRYING A LABEL MUST BE ABLE TO RUN EVERY JOB ON IT. Forgejo
# hands a `runs-on: nix` job to whichever runner with that label asks first,
# so a tool on one machine's hostPackages but not another's fails at random.
# That is why the toolset below is shared, and why dagger stays a cerberus-only
# extra: it needs the engine container from machines/cerberus/dagger.nix.
{self, ...}: let
  # Every Forgejo a runner can register with.
  #   url      what runners connect to
  #   host     the machine running it, whose own runner uses localUrl instead
  #   forgejo  command prefix that runs the `forgejo` binary there as an admin,
  #            from the workstation (`register` below appends its arguments)
  forges = {
    ugalabugala = {
      url = "https://forge.ugalabugala.org";
      host = "cerberus";
      localUrl = "http://localhost:9000";
      # `forgejo-admin` is the wrapper this module installs wherever
      # services.forgejo is enabled.
      forgejo = "ssh root@192.168.1.105 forgejo-admin";
    };
    # The in-cluster Forgejo (taghmata, nixidy apps/forgejo).
    noosphere = {
      url = "https://forge.noosphere.uk";
      host = null;
      localUrl = null;
      forgejo = "kubectl --context default -n forgejo exec -i deploy/forgejo -c forgejo -- forgejo";
    };
  };

  generatorName = forge: "forgejo-runner-${forge}";
in {
  flake.nixosModules.forgejo-runner = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkMerge mkOption mkEnableOption types genAttrs listToAttrs nameValuePair;
    cfg = config.services.imperium.forgejoRunner;
    hostName = config.networking.hostName;
    gens = config.clan.core.vars.generators;
    fcfg = config.services.forgejo;
  in {
    options.services.imperium.forgejoRunner = {
      enable = mkEnableOption "a Forgejo Actions runner registered with every forge in `forges`";

      forges = mkOption {
        type = types.listOf (types.enum (builtins.attrNames forges));
        default = builtins.attrNames forges;
        description = "Forgejo instances this runner registers with.";
      };

      # Jobs `runs-on: nix` run directly on the host (no container), so they
      # can use the host's Nix store as a build cache.
      labels = mkOption {
        type = types.listOf types.str;
        default = ["nix:host"];
      };

      extraHostPackages = mkOption {
        type = types.listOf types.package;
        default = [];
        description = "Added to the shared toolset. Read the label warning at the top of this file first.";
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        clan.core.vars.generators = listToAttrs (map (forge:
          nameValuePair (generatorName forge) {
            files."secret".secret = true;
            # Not secret: it is the public half of the secret and goes into the
            # runner config as a plain setting.
            files."uuid".secret = false;
            runtimeInputs = [pkgs.coreutils pkgs.openssl];
            # printf, not echo/heredoc: Forgejo reads --secret-file verbatim
            # and a trailing newline fails its 40-character check.
            script = ''
              set -eu
              secret="$(openssl rand -hex 20)"
              printf '%s' "$secret" > "$out/secret"
              h="$(printf '%s' "''${secret:0:16}" | od -An -tx1 | tr -d ' \n')"
              printf '%s-%s-%s-%s-%s' "''${h:0:8}" "''${h:8:4}" "''${h:12:4}" "''${h:16:4}" "''${h:20:12}" > "$out/uuid"
            '';
          })
        cfg.forges);

        services.forgejo-runner = {
          package = pkgs.forgejo-runner;
          instances.${hostName} = {
            enable = true;
            inherit (cfg) labels;
            # `secrets` values are credential paths the module turns into
            # `file:$CREDENTIALS_DIRECTORY/...` URLs. A bare path in
            # settings.token_url is rejected at startup ("unsupported secret URL").
            settings.server.connections = genAttrs cfg.forges (forge: {
              uuid = gens.${generatorName forge}.files."uuid".value;
              url =
                if forges.${forge}.host == hostName
                then forges.${forge}.localUrl
                else forges.${forge}.url;
            });
            secrets.server.connections = genAttrs cfg.forges (forge: {
              token_url = gens.${generatorName forge}.files."secret".path;
            });
            # PATH available to host-executed jobs: node (for actions/checkout),
            # devenv (the build), nix (devenv shells out to it), the usual
            # coreutils/git/tar, and a Rust toolchain for repos that build
            # their own pipeline driver (`cargo run -p ci`).
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
                mold
                cargo
                rustc
                # cargo needs a linker for build scripts (proc-macro2, libc,
                # ...). Without it every build script fails with
                # `linker 'cc' not found`. This wrapper provides cc/gcc/ld.
                stdenv.cc
              ])
              ++ cfg.extraHostPackages;
          };
        };
      })

      # `forgejo` as an admin, with the service's own environment -- what the
      # `forges.*.forgejo` command reaches over ssh. Running the binary bare
      # fails: it needs the work dir, the custom dir and the DB password, which
      # the unit only hands the web process.
      (mkIf fcfg.enable {
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "forgejo-admin" ''
            cd ${fcfg.stateDir}
            exec ${pkgs.util-linux}/bin/runuser -u ${fcfg.user} -- env \
              FORGEJO_WORK_DIR=${fcfg.stateDir} \
              FORGEJO_CUSTOM=${fcfg.customDir} \
              ${lib.optionalString (fcfg.database.passwordFile != null)
              "FORGEJO__DATABASE__PASSWD__FILE=${fcfg.database.passwordFile}"} \
              ${fcfg.package}/bin/forgejo "$@"
          '')
        ];
      })
    ];
  };

  perSystem = {
    pkgs,
    inputs',
    ...
  }: {
    # Registers runners with every forge they list. `--all` registers every
    # machine with forgejoRunner enabled, in one evaluation of all machines.
    # Idempotent, so it is safe to re-run; run it from the repo root (it reads
    # clan vars).
    packages.forgejo-runner-register = pkgs.writeShellApplication {
      name = "forgejo-runner-register";
      runtimeInputs = [inputs'.clan-core.packages.clan-cli pkgs.kubectl pkgs.openssh pkgs.jq pkgs.nix];
      text = ''
        usage="usage: forgejo-runner-register <machine>... | --all"
        [ $# -gt 0 ] || { echo "$usage" >&2; exit 1; }

        # {machine: [forge, ...]} for the requested machines that have the
        # runner enabled (all of them with --all). `or false` skips machines
        # that never import the module.
        # shellcheck disable=SC2016 # ''${n} is Nix, not shell
        enabled='(cs.''${n}.config.services.imperium.forgejoRunner.enable or false)'
        if [ "$1" = "--all" ]; then
          filter="n: $enabled"
        else
          filter="n: builtins.elem n (builtins.fromJSON '''$(jq -cn '$ARGS.positional' --args "$@")''') && $enabled"
        fi
        targets="$(nix eval --json .#nixosConfigurations --apply "cs: builtins.listToAttrs (map (n: {
          name = n;
          value = cs.\''${n}.config.services.imperium.forgejoRunner.forges;
        }) (builtins.filter ($filter) (builtins.attrNames cs)))")"

        [ "$targets" != "{}" ] || { echo "no matching machine has services.imperium.forgejoRunner enabled" >&2; exit 1; }

        jq -r 'to_entries[] | .key as $m | .value[] | "\($m) \(.)"' <<<"$targets" |
        while read -r machine forge; do
          case "$forge" in
            ${builtins.concatStringsSep "\n" (map (forge: ''
              ${forge}) forgejo="${forges.${forge}.forgejo}" ;;'') (builtins.attrNames forges))}
            *) echo "unknown forge: $forge" >&2; exit 1 ;;
          esac
          echo "registering $machine with $forge ..."
          # Via stdin, never --secret: arguments are visible in ps on the server.
          # --secret-stdin, not --secret-file /dev/stdin: forgejo-admin drops to
          # the forgejo user, which cannot reopen root's ssh pipe through /proc.
          # It is a string flag that ignores its value, hence the `=-`.
          # </dev/null: the loop's stdin is the machine list; keep clan off it.
          clan vars get "$machine" "forgejo-runner-$forge/secret" </dev/null \
            | tr -d '\n' \
            | $forgejo forgejo-cli actions register --name "$machine" --secret-stdin=-
        done
      '';
    };
  };
}
