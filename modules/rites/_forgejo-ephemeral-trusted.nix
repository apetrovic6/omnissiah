# Trusted `nix-eph` jobs (HOM-31): the CI signing key and the ncps upload
# netrc, delivered to a slot only after its exact run has been resolved as
# trusted. Imported by forgejo-runner-ephemeral.nix. Everything here is under
# `trustedJobs.enable`, so with the gate off the slot is unchanged.
#
# PAT AUTHORITY (Forgejo v15.0.12; routers/api/v1/api.go and permissions/):
#   One host-only PAT per forge. Use the configured user-scope login, or
#   manjo for an org-only forge. `write:user` includes read, for GET /user
#   and GET /user/actions/runners[/jobs], and permits user runner registration
#   and deletion. It is not a runner-only scope: even a Public only PAT can
#   POST /user/keys and DELETE /user/keys/{id}. The /user group checks user
#   scope and authentication, not checkTokenPublicOnly; the old scope comment
#   above /user/keys is not middleware. An added SSH key acts as that account
#   under its Git permissions, not under the PAT's visibility restriction.
#   Org pools additionally need `write:organization`. The dispatcher checks
#   GET /orgs/<org> for its ID; GET/POST /orgs/<org>/actions/runners,
#   DELETE .../runners/<id> and GET .../runners/jobs require owner privileges
#   (Forgejo also admits site admins). This scope lets an owner manage the
#   whole org via the API, not just runners: for example edit/delete the org,
#   manage teams and membership, and set/delete Actions secrets and variables.
#   It is not tied to the configured org: normal permissions and visibility
#   checks apply to any org the account can access.
#   Public only rejects non-public orgs on the org routes and private repos
#   on the repository lookup routes. Owner-scoped runner job listings filter
#   by owner, not by repository visibility (shared/runners.go). With
#   `read:repository`, ordinary repo GETs can read accessible public repos,
#   not just trusted ones; the deploy-key list also requires repo admin. A
#   broader visibility PAT can reach non-public resources where the account
#   has permission. `read:repository` does not grant ordinary repo writes,
#   but does not negate account SSH-key or org-owner authority.
#   In particular, DELETE /repos/<owner>/<repo> uses the owner's scope
#   (`write:user` or `write:organization`) and checks delete permission,
#   not `write:repository`. That route does not use checkTokenPublicOnly;
#   do not rely on the PAT's Public only flag to protect owned repos from it.
#   Forgejo does not offer a runner-only or specific-repo PAT with these
#   account scopes. `dispatch`, `labels`, `maxSlots` and `trust` are dispatcher
#   filters, not restrictions Forgejo enforces on the PAT.
#
# DECISION (in the dispatcher, _forgejo-ephemeral-dispatcher.py, trusted_run):
#   Every job boots untrusted. Forgejo v15.0.12's job listing has no run id
#   (routers/api/v1/shared/runners.go:73-92), so nothing reliable is known
#   before pickup. A repo absent from the pool's trust.repos stays untrusted
#   with no repo lookups. There is no up-front repository verification. After
#   pickup (job status `running`, `task_id` set), the mapping is exact:
#     job.task_id -> GET /repos/<owner>/<repo>/actions/tasks (task.run_number)
#     -> GET /repos/<owner>/<repo>/actions/runs?run_number=N (unique per repo).
#   Task and run must agree on head_sha/commit_sha and workflow_id. Only these
#   server-set run fields decide:
#     repository.id/owner, is_fork_pull_request (true for forks AND every AGit
#     PR), need_approval, event, trigger_event, ScheduleID, trigger_user.id/login,
#     prettyref, repository.default_branch.
#   The run's repo ID and owner must match its trust.repos entry; for an org
#   pool such as monolith-softworks, use the org as owner and list manjo in
#   trust.users for push/dispatch. The run must not be a fork or AGit PR or
#   await approval, and must be on the DEFAULT BRANCH ONLY (prettyref equals
#   repository.default_branch). Only a push or workflow_dispatch by someone
#   in trust.users, or a schedule triggered by forgejo-actions (-2), qualifies.
#   A dispatch accepts any ref git resolves ("pull/5/head", a PR head SHA,
#   another branch, a tag): none of those is the default branch, so none is
#   trusted. Pushes to other branches aren't trusted either. Residual: a tag
#   named exactly like the default branch looks identical; only writers can
#   create one.
#   "manjo" means any holder of a manjo write credential: the user, and any
#   agent or tool holding a manjo token with repository write. Forgejo also
#   attributes deploy-key pushes to the owner (routers/private/serv.go:266-270),
#   so any write deploy key on the repository disables trust. The dispatcher
#   lists them (GET /repos/<owner>/<repo>/keys, all pages) for every resolution;
#   an unreadable list means untrusted.
#   approved_by never grants trust, and a fork PR re-run by manjo stays a
#   fork PR. Every pull_request* event is untrusted, same-repo ones included.
#   Forge policy matters too: an auto-merge lands as a manjo push to the
#   default branch. Don't schedule auto-merges on fork PRs in a repository
#   with trust on, or require approvals with dismiss-stale-approvals.
#   Just before delivery the dispatcher rechecks that the job is still the
#   same attempt, running on the same task, and that the run is unchanged and
#   still trusted.
#   Any error (including 403 from missing scope, visibility or repo permission),
#   timeout or mismatch fails closed. Transient lookup and delivery errors
#   retry for up to 10 minutes after pickup. Untrusted jobs keep running;
#   only the credentials are withheld. The reason is logged.
#   The two credential sources are mandatory LoadCredential entries: if either
#   var is missing, systemd refuses to start the dispatcher, which stops
#   untrusted dispatch too. This module declares both (ci-credentials.nix), so
#   a missing one means it was never generated or deployed.
#
# CHANNEL: a second virtiofs share, not fw_cfg, because fw_cfg is fixed at boot.
#   Host: `trustDir`, root:root 0700. The slot host's slotctl creates it
#     empty before each boot and writes 0400 root files on a trusted verdict.
#     Readers: host root and virtiofsd (supervised by PID 1). The slot's
#     QEMU user cannot open it.
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
#     point of "trusted": it grants CI write authority to the allowed code.
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
  localSlots,
  dispatch,
  dispatching,
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
  mkTrustedSlot = slot: {
    vm,
    controlDir,
    trustDir,
    ...
  }: let
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
    services.${vm}.serviceConfig = {
      ExecStartPre = lib.mkBefore ["+${trustPreflight}"];
      # First: the base scrub is `set -eu`, and a failure there would skip later ExecStopPost lines.
      ExecStopPost = lib.mkBefore ["+${trustScrub}"];
    };
    inherit guest;
  };
  trusted = lib.mapAttrs mkTrustedSlot localSlots;
in {
  config = lib.mkIf (cfg.enable && cfg.trustedJobs.enable) (lib.mkMerge [
    {
      systemd.services = lib.mkMerge (lib.mapAttrsToList (_: data: data.services) trusted);
      microvm.vms = lib.mapAttrs (_: data: {config = data.guest;}) trusted;
    }
    (lib.mkIf dispatching {
      services.imperium.ciCredentials.enable = true;
      systemd.services."${dispatch}@".serviceConfig.LoadCredential = [
        "trusted-ci-signing-key:${ccfg.signingKey}"
        "trusted-ncps-netrc:${ccfg.ncpsNetrc}"
      ];
    })
  ]);
}
