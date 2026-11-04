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
# Dagger pipelines therefore use `runs-on: dagger`, a label only cerberus
# carries. A Dagger job on `runs-on: nix` fails on any other runner.
{self, ...}: let
  # Every Forgejo a runner can register with.
  #   url      what runners connect to
  #   host     the machine running it, whose own runner uses localUrl instead
  #   forgejo  command prefix that runs the `forgejo` binary there as an admin,
  #            from the workstation (`register` below appends its arguments)
  #   lanAddress  pinned in /etc/hosts on every other runner, or null when
  #            local DNS already answers with a LAN address
  forges = {
    ugalabugala = {
      url = "https://forge.ugalabugala.org";
      host = "cerberus";
      localUrl = "http://localhost:9000";
      # Public DNS sends this name to the VPS, so without the pin a job's
      # git and registry traffic (nopresh's image push) hairpins out through
      # Pangolin and back. cerberus pins it the same way (nopresh.nix).
      lanAddress = "192.168.1.105";
      # `forgejo-admin` is the wrapper this module installs wherever
      # services.forgejo is enabled.
      forgejo = "ssh root@192.168.1.105 forgejo-admin";
    };
    # The in-cluster Forgejo (taghmata, nixidy apps/forgejo).
    noosphere = {
      url = "https://forge.noosphere.uk";
      host = null;
      localUrl = null;
      # Technitium already resolves it to the Traefik VIP.
      lanAddress = null;
      forgejo = "kubectl --context default -n forgejo exec -i deploy/forgejo -c forgejo -- forgejo";
    };
  };

  generatorName = forge: "forgejo-runner-${forge}";

  # Binary cache the runners push their builds to. apps/ncps reads the public
  # key straight from vars/shared/${ciKeyGenerator}, so renaming the generator
  # means updating that path too.
  # ncps serves uploads under /upload only; a PUT to the root path is a 405
  # before the signature is even checked.
  ncpsUploadUrl = "https://ncps.noosphere.uk/upload";
  ciKeyGenerator = "nix-ci-signing-key";
  # `<name>-<n>`: bump the suffix to rotate while the old key is still trusted.
  ciKeyName = "ci.noosphere.uk-1";

  # Same age as the shared nix.gc (`--delete-older-than 10d`, stc/base.nix),
  # which `storeCache` replaces.
  pruneAge = "10d";
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
    # The nixpkgs module's StateDirectory for our instance (also its HOME).
    stateDir = "/var/lib/forgejo-runner/${hostName}";
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

      # For machines that have another job, above all the RKE2 nodes, which
      # are all etcd members. Runner jobs and Nix builds share one cgroup
      # slice under these caps. Memory is the hard limit (it cannot be
      # throttled, only OOM-killed); CPU also yields to everything else under
      # contention, through a low weight.
      resources = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            cpus = mkOption {
              type = types.ints.positive;
              description = "Most CPU cores CI may use, runner jobs and Nix builds combined.";
            };
            memory = mkOption {
              type = types.ints.positive;
              description = ''
                Most GiB of memory CI may use. Where RKE2 runs, the same amount
                is reserved away from kubelet, so pods are never scheduled into
                memory CI might take.
              '';
            };
          };
        });
        default = null;
      };

      # Keeps the local store warm for CI. The shared daily
      # `nix-collect-garbage --delete-older-than` deletes every unrooted path,
      # so every crane dependency build and devenv shell would be gone each
      # morning. With this set, old system generations are still pruned on
      # that schedule, but store garbage is only collected when free disk
      # space drops below `minFree`, and then up to `maxFree`. Only for
      # machines with plenty of disk.
      storeCache = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            minFree = mkOption {
              type = types.ints.positive;
              description = "GiB of free disk below which Nix starts collecting garbage.";
            };
            maxFree = mkOption {
              type = types.ints.positive;
              description = "GiB of free disk at which collection stops.";
            };
          };
        });
        default = null;
      };
    };

    config = mkMerge [
      (mkIf (cfg.enable && cfg.storeCache != null) (let
        gib = n: n * 1024 * 1024 * 1024;
      in {
        nix.settings = {
          min-free = lib.mkForce (gib cfg.storeCache.minFree);
          max-free = lib.mkForce (gib cfg.storeCache.maxFree);
        };
        nix.gc.automatic = lib.mkForce false;
        # What nix.gc did besides collecting: dropping old generations. Their
        # paths become garbage, which the min-free collection gets to later.
        systemd.services.nix-prune-generations = {
          description = "Delete system generations older than ${pruneAge}";
          startAt = "daily";
          serviceConfig.Type = "oneshot";
          script = ''
            ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system \
              --delete-generations ${pruneAge}
          '';
        };
      }))

      (mkIf cfg.enable {
        networking.hosts = mkMerge (map (forge: let
          f = forges.${forge};
        in
          mkIf (f.lanAddress != null && f.host != hostName) {
            ${f.lanAddress} = [(lib.removePrefix "https://" f.url)];
          })
        cfg.forges);
      })

      (mkIf cfg.enable {
        # CI signing key, shared by every runner. ncps
        # (taghmata nixidy apps/ncps) accepts a PUT only when the narinfo
        # carries this key's signature, so it doubles as the upload credential.
        # Separate from ncps' own serving key: a leaked runner can push into
        # the cache, but cannot forge ncps' signature on upstream paths.
        clan.core.vars.generators.${ciKeyGenerator} = {
          share = true;
          files."key".secret = true;
          files."key.pub".secret = false;
          runtimeInputs = [pkgs.nix];
          script = ''
            nix-store --generate-binary-cache-key ${ciKeyName} "$out/key" "$out/key.pub"
          '';
        };

        # The daemon signs everything it builds here with the CI key, and the
        # hook pushes it to ncps. Only daemon builds count: anything built
        # inside a container (the Dagger pipelines) has its own store and is
        # never seen here.
        nix.settings = {
          secret-key-files = [gens.${ciKeyGenerator}.files."key".path];
          post-build-hook = pkgs.writeShellScript "push-to-ncps" ''
            # Synchronous: the daemon waits for this before its next build,
            # hence the timeouts. A failed push must never fail the build, and
            # the cache falls back to upstream for whatever it misses.
            #
            # zstd, not the http store's default xz: single-threaded xz inside
            # the capped slice could not get crane's 1.7 GB dependency
            # artifacts through in 600 s, so only the tiny check stamps ever
            # reached ncps and every runner recompiled the deps itself.
            # shellcheck disable=SC2086 # OUT_PATHS is a space-separated list
            ${pkgs.coreutils}/bin/timeout 1800 \
              ${config.nix.package}/bin/nix --extra-experimental-features nix-command \
              copy --option connect-timeout 5 \
              --to '${ncpsUploadUrl}?compression=zstd&parallel-compression=true' $OUT_PATHS \
              || echo "push-to-ncps: upload failed (exit $?), continuing" >&2
          '';
        };
      })

      (mkIf (cfg.enable && cfg.resources != null) (let
        r = cfg.resources;
      in {
        systemd.slices.forgejo-ci.sliceConfig = {
          CPUQuota = "${toString (r.cpus * 100)}%";
          CPUWeight = 20;
          IOWeight = 20;
          # Throttle (reclaim) half a GiB before the hard cap starts OOM-killing.
          MemoryHigh = "${toString (r.memory * 1024 - 512)}M";
          MemoryMax = "${toString r.memory}G";
        };
        # The daemon has to be in the slice too: Nix builds run in its cgroup,
        # not the runner's. Deploy-time store copies go through it as well,
        # which is harmless, since they need little memory.
        systemd.services."forgejo-runner-${hostName}".serviceConfig.Slice = "forgejo-ci.slice";
        systemd.services.nix-daemon.serviceConfig.Slice = "forgejo-ci.slice";
        nix = {
          settings = {
            max-jobs = 1;
            cores = r.cpus;
          };
          daemonCPUSchedPolicy = "batch";
          daemonIOSchedClass = "idle";
        };
        # cargo run directly by jobs (outside Nix) otherwise starts one rustc
        # per core of the whole machine, and they share the memory cap.
        services.forgejo-runner.instances.${hostName}.settings.runner.envs.CARGO_BUILD_JOBS = toString r.cpus;

        # Lowers what kubelet offers the scheduler. Pods already on the node
        # stay where they are; changing this restarts rke2, so roll it out one
        # etcd member at a time.
        services.rke2.extraFlags = mkIf config.services.rke2.enable [
          "--kubelet-arg=system-reserved=memory=${toString r.memory}Gi"
        ];
      }))

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
            # The instance's own `labels` option was renamed to
            # `settings.runner.labels` upstream. Nothing else changes: the
            # nixpkgs module reads the labels back through
            # `settings.runner.labels` plus any per-connection
            # `settings.server.connections.<n>.labels`, and derives
            # `runtimes.host` from a `:host` suffix and `runtimes.docker` /
            # `runtimes.podman` from a `:docker` infix off that same list.
            settings.runner.labels = cfg.labels;
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
                # Host steps outside a devenv shell had no `diff` (fishing's
                # and rust-app-template's reported `diff: command not found`),
                # and rust-app-template ended up parsing JSON with grep. Shared
                # list, not extraHostPackages: every runner carries `nix:host`,
                # so a tool on one machine alone fails those jobs at random.
                diffutils
                jq
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
            # DynamicUser gives the service a private /tmp and /var/tmp, and
            # they are a tmpfs sized at a fraction of RAM (1.5 GiB on sol), not
            # the disk. A job's `mktemp -d` cargo build (check-template's
            # generated product) fills it: rustc fails with "No space left on
            # device" and lld with SIGBUS writing its mmap'd output. Point jobs
            # at the state dir instead, which is on disk.
            settings.runner.envs.TMPDIR = "${stateDir}/tmp";
          };
        };
        # As the service's own (dynamic) user, so the directory is theirs.
        systemd.services."forgejo-runner-${hostName}".serviceConfig.ExecStartPre = [
          "${pkgs.coreutils}/bin/mkdir -p ${stateDir}/tmp"
        ];
        # `e`: clean an existing directory without creating or owning it.
        # Whatever a job left behind goes after a day.
        systemd.tmpfiles.rules = ["e ${stateDir}/tmp - - - 1d"];
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
          # It prints the runner uuid with no trailing newline.
          echo
        done
      '';
    };
  };
}
