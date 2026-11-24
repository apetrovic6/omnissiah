# Forgejo Actions runners, one service per forge on each machine.
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
# That is why the toolset below is shared and per-machine extras are rare.
{self, ...}: let
  # Every Forgejo a runner can register with.
  #   url      what runners connect to
  #   host     the machine running it, whose own runner uses localUrl instead
  #   forgejo  command prefix that runs the `forgejo` binary there as an admin,
  #            from the workstation (`register` below appends its arguments)
  #   lanAddress  pinned in /etc/hosts on every other runner, or null when
  #              local DNS already answers with a LAN address
  #   scope    owner or owner/repo for offline registration; absent means global
  forges = {
    ugalabugala = {
      url = "https://forge.${self.lib.lab.domain}";
      host = "cerberus";
      localUrl = "http://localhost:9000";
      # Public DNS sends this name to the VPS, so without the pin a job's
      # git and registry traffic (nopresh's image push) hairpins out through
      # Pangolin and back. cerberus pins it the same way (nopresh.nix).
      lanAddress = self.lib.hosts.cerberus;
      sccachePort = 4228;
      # Hermes owns its forks, and runners have no repository allowlist.
      # Other owners need their own scoped registration if they enable Actions.
      scope = "manjo";
      # `forgejo-admin` is the wrapper this module installs wherever
      # services.forgejo is enabled.
      forgejo = "ssh root@${self.lib.hosts.cerberus} forgejo-admin";
    };
    # The in-cluster Forgejo (taghmata, nixidy apps/scriptorium/forgejo).
    noosphere = {
      url = "https://forge.noosphere.uk";
      host = null;
      localUrl = null;
      # Technitium already resolves it to the Traefik VIP.
      lanAddress = null;
      sccachePort = 4227;
      forgejo = "kubectl --context default -n forgejo exec -i deploy/forgejo -c forgejo -- forgejo";
    };
  };

  generatorName = forge: "forgejo-runner-${forge}";

  # Binary cache the runners push their builds to. apps/scriptorium/ncps reads the public
  # key straight from vars/shared/${ciKeyGenerator}, so renaming the generator
  # means updating that path too.
  # ncps serves uploads under /upload only; a PUT to the root path is a 405
  # before the signature is even checked.
  ncpsUploadUrl = "https://ncps.noosphere.uk/upload";
  # Basic auth on /upload. The generator lives with the Traefik side in
  # taghmata/reliquary/ncps (nixosModules.reliquary-ncps), which this module
  # imports. Only the push hook gets the netrc, not nix as a whole.
  ncpsUploadAuth = "ncps-upload-auth";
  ciKeyGenerator = "nix-ci-signing-key";
  # `<name>-<n>`: bump the suffix to rotate while the old key is still trusted.
  ciKeyName = "ci.noosphere.uk-1";

  # Same age as the shared nix.gc (`--delete-older-than 10d`, stc/base.nix),
  # which `storeCache` replaces.
  pruneAge = "10d";

  # Where secrets reach a runner that runs inside a microVM: qemu hands them
  # to the guest as systemd credentials (forgejo-runner-microvm.nix), which
  # PID 1 exposes to root under this directory.
  guestCredentialDir = "/run/credentials/@system";

  # Everything a runner needs to RUN, as opposed to its identity (the clan
  # vars, registration), which always lives on the clan machine. Called with
  # the config of whichever system runs the jobs: the machine itself
  # (`isolation = "host"`) or its CI microVM (`isolation = "microvm"`). The
  # same function on both sides is what keeps the toolset identical, which
  # the label warning at the top of this file depends on.
  #
  #   runForges  the connections this system runs (one per guest)
  #   machine  the clan machine whose identity this is, for the forge URLs
  #   cfg      that machine's services.imperium.forgejoRunner
  #   resources  host CI budget or this guest's share
  #   sccache  null, or that machine's services.imperium.sccache
  #   paths    where the secrets are, on the system that runs the jobs
  #   inVm     the system is a dedicated CI VM, so there is nothing to share
  #            CPU and memory with: no slice, no kubelet reservation
  runtimeConfig = {
    config,
    lib,
    pkgs,
    runForges,
    machine,
    cfg,
    resources,
    sccache,
    paths,
    inVm,
  }: let
    inherit (lib) mkIf mkMerge;
    systemConfig = [
      {
        networking.hosts = mkMerge (map (forge: let
          f = forges.${forge};
        in
          mkIf (f.lanAddress != null && f.host != machine) {
            ${f.lanAddress} = [(lib.removePrefix "https://" f.url)];
          })
        cfg.forges);
        services.forgejo-runner.package = pkgs.forgejo-runner;
      }

      {
        # The daemon signs everything it builds here with the CI key, and the
        # hook pushes it to ncps. Only daemon builds count: a cargo build run
        # directly by a job step never goes through the daemon.
        #
        # `secret-key` in the URL, not only nix.settings.secret-key-files above:
        # a narinfo goes up with whatever signature the local store already
        # holds for it, and the daemon records one only for paths it built
        # itself. A path that arrived another way -- the closure copy a clan
        # deploy pushes over ssh, a substitution from cache.nixos.org that ncps
        # never proxied -- holds none, so ncps answers with
        #   HTTP 500 rejecting untrusted narinfo: narinfo has no trusted signature
        # nix aborts the copy mid-closure, and the root of that closure -- the
        # system toplevel, always copied last -- never lands. Measured on
        # cerberus: 23623 CI-pushed paths in ncps, none of them a
        # `nixos-system-*`, while every check job built its toplevel fine. Give
        # the copy the key and it signs those paths too; the same 10 GB cerberus
        # closure then finishes uploading in 32 s, toplevel included.
        nix.settings = {
          secret-key-files = [paths.ciKey];
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
              --option netrc-file ${paths.ncpsNetrc} \
              --to '${ncpsUploadUrl}?compression=zstd&parallel-compression=true&secret-key=${paths.ciKey}' $OUT_PATHS \
              || echo "push-to-ncps: upload failed (exit $?), continuing" >&2
          '';
        };
      }

      (mkIf (resources != null) (let
        r = resources;
      in
        mkMerge [
          {
            nix = {
              settings = {
                # One build slot per runner. On hosts, builds from both
                # forges share this daemon and the same capped slice.
                # Both may build at once with r.cpus cores each. Their
                # memory must fit the same slice: concurrent Rust builds
                # can hit MemoryHigh or OOM on Luna's 3 GiB. If that happens,
                # use max 1 (r.cpus / length runForges) cores per build;
                # a lone build then gets fewer cores too.
                max-jobs = builtins.length runForges;
                cores = r.cpus;
              };
              daemonCPUSchedPolicy = "batch";
              daemonIOSchedClass = "idle";
            };
          }

          # In a VM, the VM's own size is the cap (forgejo-runner-microvm.nix).
          (mkIf (!inVm) {
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
            systemd.services.nix-daemon.serviceConfig.Slice = "forgejo-ci.slice";

            # Lowers what kubelet offers the scheduler. Pods already on the node
            # stay where they are; changing this restarts rke2, so roll it out one
            # etcd member at a time.
            #
            # mkAfter pins the flag to the end of the command line. Without it the
            # position follows module import order, and moving an import would
            # change the unit and restart rke2 for nothing.
            services.rke2.extraFlags = mkIf (config.services.rke2.enable or false) (lib.mkAfter [
              "--kubelet-arg=system-reserved=memory=${toString r.memory}Gi"
            ]);
          })
        ]))
    ];

    instanceConfig = forge: let
      unit = "forgejo-runner-${forge}";
      # The nixpkgs module's StateDirectory for this instance (also its HOME).
      stateDir = "/var/lib/forgejo-runner/${forge}";
      cargoState = "forgejo-runner-cargo-${forge}";
      cargoHome = "/var/lib/${cargoState}";
    in {
      inherit unit;
      instance = mkMerge [
        {
          enable = true;
          # The instance's own `labels` option was renamed to
          # `settings.runner.labels` upstream. Nothing else changes: the
          # nixpkgs module reads the labels back through
          # `settings.runner.labels` plus any per-connection
          # `settings.server.connections.<n>.labels`, and derives
          # `runtimes.host` from a `:host` suffix and `runtimes.docker` /
          # `runtimes.podman` from a `:docker` infix off that same list.
          settings.runner.labels = cfg.labels;
          # forgejo-runner's job timeout defaults to 3h (its config.example
          # says so, and nothing here overrode it), which is what killed the
          # phalanx and enginseer builds:
          #   [runner]: this step has been cancelled: ctx: context deadline
          #   exceeded, exec: RUN signal: killed
          # Three deadlines apply to one job -- the instance's
          # `ENDLESS_TASK_TIMEOUT`, this one, and the workflow's
          # `timeout-minutes` -- and the shortest wins, so this is kept above
          # the workflow's 5h: the workflow owns the deadline you see in the
          # UI, and the runner never cuts a job short underneath it.
          settings.runner.timeout = "6h";
          settings.runner.capacity = cfg.capacity;
          # `secrets` values are credential paths the module turns into
          # `file:$CREDENTIALS_DIRECTORY/...` URLs. A bare path in
          # settings.token_url is rejected at startup ("unsupported secret URL").
          settings.server.connections.${forge} = {
            uuid = paths.forgeUuid forge;
            url =
              if forges.${forge}.host == machine
              then forges.${forge}.localUrl
              else forges.${forge}.url;
          };
          secrets.server.connections.${forge}.token_url = paths.forgeSecret forge;
          # PATH available to host-executed jobs: node (for actions/checkout),
          # devenv (the build), nix (devenv shells out to it), the usual
          # coreutils/git/tar, and a Rust toolchain for steps that run cargo
          # outside a devenv shell.
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
              gawk
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
          # Bound Cargo's default parallelism to the CI budget, not the host.
          settings.runner.envs.CARGO_BUILD_JOBS = mkIf (resources != null) (toString resources.cpus);
        }

        # sccache: the shared compilation cache in the `sccache` bucket on
        # garage-main, for the host steps that run cargo outside the Nix sandbox
        # (Nix builds are ncps' job). Generator and values: modules/rites/sccache.nix.
        #
        # Credentials: the DynamicUser cannot own files, and /run/secrets is
        # root-only, so the var file travels through systemd LoadCredential and
        # the job steps read it at $CREDENTIALS_DIRECTORY/sccache-credentials.
        # The path is handed to jobs as a plain unit-level Environment=, NOT
        # through settings.runner.envs: the runner writes those into job env
        # verbatim, and "$CREDENTIALS_DIRECTORY/..." would arrive unexpanded.
        # Unit-level Environment= reaches the steps because act merges the
        # daemon's own environment into every job (act/runner/run_context.go,
        # the os.Environ() loop, "don't override").
        (mkIf (sccache != null) {
          # The wrapper, not bare sccache (modules/rites/sccache.nix): it
          # unsets CARGO_INSTALL_ROOT -- the job's `devenv shell` sets it to
          # <act work dir>/.devenv/state/cargo-install, a per-job path that
          # sccache 0.19 hashes into every cache key, which is what stopped
          # jobs from sharing even registry deps -- and the ambient AWS_*
          # variables that reqsign's env provider would otherwise prefer
          # over the unit's AWS_SHARED_CREDENTIALS_FILE.
          hostPackages = [sccache.wrapper];
          settings.runner.envs = {
            RUSTC_WRAPPER = "${sccache.wrapper}/bin/sccache";
            SCCACHE_BUCKET = sccache.bucket;
            SCCACHE_ENDPOINT = sccache.endpoint;
            SCCACHE_REGION = sccache.region;
            # A job that cannot reach Garage (a runner away from the LAN, an
            # outage) must still compile -- uncached, not red.
            SCCACHE_IGNORE_SERVER_IO_ERROR = "1";
            # sccache hashes Cargo paths: this writable state is consistent
            # across machines for one forge, but cold after the split and
            # no longer shares entries across forges.
            CARGO_HOME = cargoHome;
            # Do not connect to the other runner's local sccache server.
            SCCACHE_SERVER_PORT = toString forges.${forge}.sccachePort;
          };
        })
      ];

      service = mkMerge [
        {
          serviceConfig = {
            # Both units can burst within the same cap, alongside nix-daemon.
            Slice = mkIf (!inVm && resources != null) "forgejo-ci.slice";
            # Run as the service's dynamic user.
            ExecStartPre = ["${pkgs.coreutils}/bin/mkdir -p ${stateDir}/tmp"];
          };
        }
        (mkIf (sccache != null) {
          # The wrapper only DEFAULTS AWS_SHARED_CREDENTIALS_FILE when unset
          # (`:-`) and never touches it otherwise, so this unit-level value
          # -- unreadable /run/secrets path swapped for the LoadCredential
          # mount -- is what the job's sccache server ends up using.
          environment.AWS_SHARED_CREDENTIALS_FILE = "/run/credentials/${unit}.service/sccache-credentials";
          serviceConfig = {
            LoadCredential = [
              "sccache-credentials:${paths.sccacheCredentials}"
            ];
            StateDirectory = [cargoState];
            # Same reason the nixpkgs module lists the state dir here: under
            # DynamicUser the id-mapped mounts are noexec, and CARGO_HOME/bin
            # tools a job cargo-installs have to run.
            ExecPaths = [cargoHome];
          };
        })
      ];
      # `e` cleans an existing directory without creating or owning it.
      tmpRule = "e ${stateDir}/tmp - - - 1d";
    };
    instances = lib.genAttrs runForges instanceConfig;
  in
    mkMerge (systemConfig
      ++ [
        {
          services.forgejo-runner.instances = lib.mapAttrs (_: data: data.instance) instances;
          systemd.services = lib.mapAttrs' (_: data: lib.nameValuePair data.unit data.service) instances;
          systemd.tmpfiles.rules = lib.mapAttrsToList (_: data: data.tmpRule) instances;
        }
      ]);
in {
  flake.nixosModules.forgejo-runner = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkMerge mkOption mkEnableOption types listToAttrs nameValuePair;
    cfg = config.services.imperium.forgejoRunner;
    scfg = config.services.imperium.sccache;
    sccacheOn = config.services.imperium.sccache.enable or false;
    hostName = config.networking.hostName;
    gens = config.clan.core.vars.generators;
    fcfg = config.services.forgejo;

    # Credential ids for one guest, and the Clan vars they come from. QEMU
    # hands these back under guestCredentialDir, with no other forge's token.
    credentialSources = forge:
      {
        ${generatorName forge} = gens.${generatorName forge}.files."secret".path;
        ci-signing-key = gens.${ciKeyGenerator}.files."key".path;
        ncps-netrc = gens.${ncpsUploadAuth}.files.netrc.path;
      }
      // lib.optionalAttrs sccacheOn {
        sccache-credentials = gens.sccache-garage-key.files.credentials.path;
      };

    sccacheFor =
      if sccacheOn
      then {inherit (scfg) wrapper bucket endpoint region;}
      else null;
  in {
    # The ncps signing key and upload credentials the post-build hook uses.
    imports = [self.nixosModules.reliquary-ncps];

    options.services.imperium.forgejoRunner = {
      enable = mkEnableOption "one Forgejo Actions runner per forge in `forges`";

      forges = mkOption {
        type = types.listOf (types.enum (builtins.attrNames forges));
        default = builtins.attrNames forges;
        description = "Forgejo instances this machine runs a runner for.";
      };

      # Jobs `runs-on: nix` run directly on the host (no container), so they
      # can use the host's Nix store as a build cache.
      labels = mkOption {
        type = types.listOf types.str;
        default = ["nix:host"];
      };

      # Each forge polls independently, even when another forge is busy.
      capacity = mkOption {
        type = types.ints.positive;
        default = 1;
        description = "Jobs each forge's runner runs at once.";
      };

      extraHostPackages = mkOption {
        type = types.listOf types.package;
        default = [];
        description = "Added to the shared toolset. Read the label warning at the top of this file first.";
      };

      # Where the jobs run. `host`: on this machine, next to everything else
      # it runs. `microvm`: in one dedicated VM per forge, with its own kernel,
      # so a job cannot see other guests' or the host's files and processes.
      # See `resources` for the combined guest budget. Needs
      # self.nixosModules.forgejo-runner-microvm imported, and /dev/kvm.
      isolation = mkOption {
        type = types.enum ["host" "microvm"];
        default = "host";
      };

      # For machines that have another job, above all the RKE2 nodes, which
      # are all etcd members. Runner jobs and Nix builds share one cgroup
      # slice under these caps. Memory is the hard limit (it cannot be
      # throttled, only OOM-killed); CPU also yields to everything else under
      # contention, through a low weight. With `isolation = "microvm"` these
      # resources are divided across the guests instead.
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
      # machines with plenty of disk. Host isolation only.
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

      # Read by forgejo-runner-microvm.nix.
      guests = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            module = mkOption {
              type = types.deferredModule;
              description = "The runner's runtime as a NixOS guest module.";
            };
            credentialSources = mkOption {
              type = types.attrsOf types.str;
              description = "Credential ids and host paths for this guest.";
            };
          };
        });
        internal = true;
        readOnly = true;
        description = "CI guests by forge.";
      };
    };

    config = mkMerge [
      {
        services.imperium.forgejoRunner.guests =
          lib.genAttrs
          (lib.optionals (cfg.enable && cfg.isolation == "microvm") cfg.forges)
          (forge: {
            credentialSources = credentialSources forge;
            module = {
              config,
              lib,
              pkgs,
              ...
            }: {
              config = runtimeConfig {
                inherit config lib pkgs cfg;
                runForges = [forge];
                machine = hostName;
                resources = {
                  cpus = config.microvm.vcpu;
                  memory = config.microvm.mem / 1024;
                };
                sccache = sccacheFor;
                inVm = true;
                paths = {
                  forgeSecret = f: "${guestCredentialDir}/${generatorName f}";
                  forgeUuid = f: gens.${generatorName f}.files."uuid".value;
                  ciKey = "${guestCredentialDir}/ci-signing-key";
                  ncpsNetrc = "${guestCredentialDir}/ncps-netrc";
                  sccacheCredentials = "${guestCredentialDir}/sccache-credentials";
                };
              };
            };
          });
      }

      (mkIf (cfg.enable && cfg.isolation == "host" && cfg.storeCache != null) (let
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

      # The runner's identity: on the clan machine whatever the isolation,
      # since the clan vars and `forgejo-runner-register` live here.
      (mkIf cfg.enable {
        # CI signing key, shared by every runner. ncps
        # (taghmata nixidy apps/scriptorium/ncps) accepts a PUT only when the narinfo
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
      })

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
      })

      (mkIf (cfg.enable && cfg.isolation == "host") (runtimeConfig {
        inherit config lib pkgs cfg;
        runForges = cfg.forges;
        machine = hostName;
        resources = cfg.resources;
        sccache = sccacheFor;
        inVm = false;
        paths = {
          forgeSecret = forge: gens.${generatorName forge}.files."secret".path;
          forgeUuid = forge: gens.${generatorName forge}.files."uuid".value;
          ciKey = gens.${ciKeyGenerator}.files."key".path;
          ncpsNetrc = gens.${ncpsUploadAuth}.files.netrc.path;
          sccacheCredentials = gens.sccache-garage-key.files.credentials.path;
        };
      }))

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
    lib,
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
            ${lib.concatMapStringsSep "\n" (forge: let
          f = forges.${forge};
          args = lib.optionals (f ? scope) ["--scope" f.scope];
        in ''
          ${forge})
            forgejo="${f.forgejo}"
            register_args=(${lib.escapeShellArgs args})
            ;;
        '') (builtins.attrNames forges)}
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
            | $forgejo forgejo-cli actions register --name "$machine" --secret-stdin=- --keep-labels "''${register_args[@]}"
          # It prints the runner uuid with no trailing newline.
          echo
        done
      '';
    };
  };
}
