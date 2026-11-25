# Trusted `nix-eph` jobs (HOM-31): the CI signing key and the ncps upload
# netrc, delivered to a slot only after its exact run has been resolved as
# trusted. Imported by forgejo-runner-ephemeral.nix. Everything here is under
# `trustedJobs.enable`, so with the gate off the slot is unchanged.
#
# DECISION (in the dispatcher, _forgejo-ephemeral-dispatcher.py, trusted_run):
#   Every job boots untrusted. Forgejo v15.0.12's job listing has no run id
#   (routers/api/v1/shared/runners.go:73-92), so nothing reliable is known
#   before pickup. After the slot's runner has taken the job (job status
#   `running`, `task_id` set), the mapping is exact:
#     job.task_id -> GET /repos/manjo/<repo>/actions/tasks (task.run_number)
#     -> GET /repos/manjo/<repo>/actions/runs?run_number=N (unique per repo).
#   Task and run must agree on head_sha/commit_sha and workflow_id. Only these
#   server-set run fields decide:
#     repository.id/owner, is_fork_pull_request (true for forks AND every AGit
#     PR), need_approval, event, trigger_event, ScheduleID, trigger_user.id,
#     prettyref, repository.default_branch.
#   Trusted means not a fork or AGit PR, not awaiting approval, on the
#   DEFAULT BRANCH ONLY (prettyref == repository.default_branch), and one of:
#     a push by manjo; a schedule (trigger user forgejo-actions, -2); a
#     workflow_dispatch by manjo.
#   A dispatch accepts any ref git resolves ("pull/5/head", a PR head SHA,
#   another branch, a tag): none of those is the default branch, so none is
#   trusted. Pushes to other branches aren't trusted either. Residual: a tag
#   named exactly like the default branch looks identical; only writers can
#   create one.
#   "manjo" means any holder of a manjo write credential: the user, and any
#   agent or tool holding a manjo token with repository write. Forgejo also
#   attributes deploy-key pushes to the owner (routers/private/serv.go:266-270),
#   so any write deploy key on the repository disables trust. The dispatcher
#   lists them (GET /repos/manjo/<repo>/keys, all pages) for every resolution;
#   an unreadable list means untrusted.
#   approved_by never grants trust, and a fork PR re-run by manjo stays a
#   fork PR. Every pull_request* event is untrusted, same-repo ones included.
#   Forge policy matters too: an auto-merge lands as a manjo push to the
#   default branch. Don't schedule auto-merges on fork PRs in a repository
#   with trust on, or require approvals with dismiss-stale-approvals.
#   Just before delivery the dispatcher rechecks that the job is still the
#   same attempt, running on the same task, and that the run is unchanged and
#   still trusted.
#   Any error, a 403 (the PAT lacks read:repository), a timeout or a mismatch
#   means nothing is delivered. Lookups retry for 10 minutes after pickup, then
#   the dispatcher gives up. Delivery errors (for example a missing trust dir)
#   count against the same deadline. Untrusted jobs keep running; only the
#   credentials are withheld. The reason is logged.
#   The two credential sources are mandatory LoadCredential entries: if either
#   var is missing, systemd refuses to start the dispatcher, which stops
#   untrusted dispatch too. This module declares both (ci-credentials.nix), so
#   a missing one means it was never generated or deployed.
#
# CHANNEL: a second virtiofs share, not fw_cfg, because fw_cfg is fixed at boot.
#   Host: `trustDir`, root:root 0700. The dispatcher creates it empty before
#     each boot and writes 0400 root files into it on a trusted verdict.
#     Readers: root, which means the dispatcher, PID 1 and virtiofsd (root,
#     supervisord). QEMU's user (microvm-eph) cannot open it.
#   Guest: mounted read-only (virtiofsd --readonly, cache=never, no ACLs/xattrs,
#     ro,nosuid,nodev,noexec) at /run/ci-trust. The guest sees the host's
#     modes and uids, and the kernel enforces them on virtiofs: Linux v6.18
#     fs/fuse/virtio_fs.c:1531 sets default_permissions. So only guest root
#     can read it. In practice that is the nix-daemon's post-build hook, the
#     only consumer.
#   The job's steps run as forgejo-one-job: unprivileged, NoNewPrivileges, not
#     in nix trusted-users (asserted), so it cannot override post-build-hook,
#     netrc-file or secret-key-files either. It cannot read the files. A trusted
#     job can still have anything it builds signed and pushed. That is the
#     point of "trusted", and equals manjo pushing to master.
#   Untrusted jobs: the share stays empty for the whole boot. Not even guest
#     root has anything to read.
#   Removal: the slot's ExecStopPost trust scrub (ordered first, always
#     exits 0), the dispatcher's idle scrub (which also removes the
#     directory), and at dispatcher start (files only; a still-running
#     trusted job is then re-resolved and re-delivered).
#   Escapes:
#     - QEMU (microvm-eph) can reach the virtiofsd sockets in the root:microvm-eph
#       0750 slot directory. So it can read what virtiofsd serves: the host store,
#       as today, and the share, which holds keys only while a trusted job is
#       running. It cannot open trustDir directly.
#     - virtiofsd runs as root on Ryza inside its own sandbox. Escaping it
#       is root on the host: everything, including the key sources, the
#       dispatcher PAT and the persistent runners' secrets. The share adds a
#       second virtiofsd of the same kind as the store's, nothing new in kind.
#
# NOT HERE (HOM-32): sccache on nix-eph (Garage is unreachable from the slot's
# source address; a read-only key on the shared bucket would expose every
# object). The two credentials come from ci-credentials.nix, which this
# module enables, so they no longer depend on the persistent runner.
{
  cfg,
  slot,
  vm,
  dispatch,
  controlDir,
  trustDir,
  cacheHost,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  ccfg = config.services.imperium.ciCredentials;
  guestTrustDir = "/run/ci-trust";
  names = ["ci-signing-key" "ncps-netrc" ".ci-signing-key.tmp" ".ncps-netrc.tmp"];
  # Same pattern and caveat as the slot scrub (forgejo-runner-ephemeral.nix):
  # never fail the stop path; the dispatcher's scrub removes what is left.
  trustScrub = pkgs.writeShellScript "${slot}-trust-scrub" ''
    set -u
    if [[ -d ${trustDir} && ! -L ${trustDir} ]]; then
      ${lib.getExe' pkgs.coreutils "rm"} -f -- ${lib.escapeShellArgs (map (name: "${trustDir}/${name}") names)}
      ${lib.getExe' pkgs.coreutils "rmdir"} -- ${trustDir} \
        || printf 'Leaving %s for the dispatcher scrub\n' ${trustDir} >&2
    fi
  '';
  # A boot must start with an empty share: anything else may be another job's keys.
  trustPreflight = pkgs.writeShellScript "${slot}-trust-preflight" ''
    set -eu
    [[ -d ${trustDir} && ! -L ${trustDir} ]]
    [[ "$(${lib.getExe' pkgs.coreutils "stat"} -c '%u %a' ${trustDir})" == "0 700" ]]
    [[ -z "$(${lib.getExe' pkgs.findutils "find"} ${trustDir} -mindepth 1 -print -quit)" ]]
  '';
  guest = {
    config,
    lib,
    pkgs,
    ...
  }: {
    microvm.shares = [
      {
        tag = "ci-trust";
        socket = "${controlDir}/${slot}-virtiofs-ci-trust.sock";
        source = trustDir;
        mountPoint = guestTrustDir;
        proto = "virtiofs";
        readOnly = true;
        # New files must show up mid-boot: no cached negative lookups.
        cache = "never";
        posixAcl = false;
      }
    ];
    # nofail: a missing share must not stop the job from running (it just won't upload).
    fileSystems.${guestTrustDir}.options = lib.mkAfter ["ro" "nosuid" "nodev" "noexec" "nofail"];
    # Uploads only once both credentials are present and well formed. The URL's
    # secret-key signs on upload, so no secret-key-files (forgejo-runner.nix
    # explains why the persistent runners pass it the same way).
    nix.settings.post-build-hook = pkgs.writeShellScript "push-to-ncps" ''
      set -u
      key=${guestTrustDir}/ci-signing-key
      netrc=${guestTrustDir}/ncps-netrc
      # Bounded: a wedged share must not hang every build.
      t=${lib.getExe' pkgs.coreutils "timeout"}
      { "$t" 5 ${lib.getExe' pkgs.coreutils "test"} -f "$key" && "$t" 5 ${lib.getExe' pkgs.coreutils "test"} -f "$netrc"; } || exit 0
      "$t" 5 ${lib.getExe' pkgs.gnugrep "grep"} -qxE '[A-Za-z0-9._-]+:[A-Za-z0-9+/]+={0,2}' "$key" || exit 0
      "$t" 5 ${lib.getExe' pkgs.gnugrep "grep"} -qx 'machine ${cacheHost}' "$netrc" || exit 0
      # 1800 s like the persistent runners' hook (forgejo-runner.nix), sized for large dependency closures.
      # shellcheck disable=SC2086 # OUT_PATHS is a space-separated list
      "$t" 1800 \
        ${config.nix.package}/bin/nix --extra-experimental-features nix-command \
        copy --option connect-timeout 5 --option netrc-file "$netrc" \
        --to "https://${cacheHost}/upload?compression=zstd&parallel-compression=true&secret-key=$key" $OUT_PATHS \
        || echo "push-to-ncps: upload failed (exit $?), continuing" >&2
      exit 0
    '';
    assertions = [
      {
        assertion = lib.all (user: !(builtins.elem user config.nix.settings.trusted-users)) ["forgejo-one-job" "@forgejo-one-job" "*"];
        message = "forgejoEphemeral: the job user must not be a Nix trusted user (it could replace the upload hook).";
      }
    ];
  };
in {
  config = lib.mkIf (cfg.enable && cfg.trustedJobs.enable) {
    services.imperium.ciCredentials.enable = true;
    # List options: these merge with the definitions in forgejo-runner-ephemeral.nix.
    systemd.services.${dispatch}.serviceConfig.LoadCredential = [
      "trusted-ci-signing-key:${ccfg.signingKey}"
      "trusted-ncps-netrc:${ccfg.ncpsNetrc}"
    ];
    systemd.services.${vm}.serviceConfig = {
      ExecStartPre = lib.mkBefore ["+${trustPreflight}"];
      # First: the base scrub is `set -eu`, and a failure there would skip later ExecStopPost lines.
      ExecStopPost = lib.mkBefore ["+${trustScrub}"];
    };
    microvm.vms.${slot}.config = guest;
  };
}
