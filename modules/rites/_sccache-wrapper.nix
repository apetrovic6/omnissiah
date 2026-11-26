# Shared by credentialed workstation, persistent CI and one-job CI runners.
{
  lib,
  pkgs,
  credentialsFile,
  requireCredentials ? false,
}:
pkgs.writeShellScriptBin "sccache" (
  lib.optionalString requireCredentials ''
    # No key until this exact run has been resolved as trusted. Never start a
    # server with ambient credentials (or a local cache) before delivery.
    if [ ! -r ${lib.escapeShellArg credentialsFile} ]; then
      case "''${1:-}" in
        "" | -*) echo "sccache: no trusted CI cache credentials" >&2; exit 1 ;;
        *) exec "$@" ;;
      esac
    fi
    export AWS_SHARED_CREDENTIALS_FILE=${lib.escapeShellArg credentialsFile}
  ''
  + ''
    # 1. Cache keys. sccache 0.19 hashes EVERY CARGO_* env var of the
    #    client process verbatim into the Rust key (compiler/rust.rs;
    #    the client snapshots its own environment in cmdline.rs and
    #    sends it with the compile request -- the wrapper IS the client
    #    process, so unsetting here really removes it from the key).
    #    devenv's languages.rust exports
    #    CARGO_INSTALL_ROOT=<project>/.devenv/state/cargo-install, and
    #    CI jobs run `devenv shell` in per-job act work dirs, so
    #    without this unset every key carries the checkout path and
    #    nothing is shared between worktrees or jobs. rustc never reads
    #    CARGO_INSTALL_ROOT -- it only steers where `cargo install`
    #    puts binaries, which happens in the shell, not through the
    #    wrapper -- so dropping it on the rustc side is safe.
    unset CARGO_INSTALL_ROOT

    # 2. Credential chain. reqsign's default AWS chain (via opendal)
    #    is env -> profile -> sso -> web-identity -> process -> ecs ->
    #    imds: AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the ambient
    #    environment (e.g. the tofunix S3 key from the omnissiah
    #    .envrc) BEAT the AWS_SHARED_CREDENTIALS_FILE profile the
    #    server is supposed to use, and server startup then fails
    #    ("refreshed signing credential expires before the requested
    #    operation deadline"). That failure is NOT covered by
    #    SCCACHE_IGNORE_SERVER_IO_ERROR -- it only downgrades IO errors
    #    while talking to an already-running server -- so every cargo
    #    build fails hard, and a server that does come up with the
    #    wrong env keeps serving every later client on
    #    127.0.0.1:4226 until its idle timeout. AWS_PROFILE goes too:
    #    the credentials file has only [default], and a foreign profile
    #    would send the profile provider looking for a section that
    #    does not exist, falling through the rest of the chain.
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

    # 3. Credentials. Keep an AWS_SHARED_CREDENTIALS_FILE that is
    #    already set (the runners hand it to the unit through systemd
    #    LoadCredential + Environment=; the wrapper never unsets it);
    #    otherwise fall back to this machine's deployed clan var file
    #    (the workstations: user-owned there, and the sccache server
    #    opens it directly). Scoped to sccache's own process tree -- a
    #    session-wide export would redirect the aws CLI and every AWS
    #    SDK tool to a key that can see exactly one bucket.
    export AWS_SHARED_CREDENTIALS_FILE="''${AWS_SHARED_CREDENTIALS_FILE:-${credentialsFile}}"

    # 4. Garage unreachable = uncached, never a failed build (RT-77).
    #    sccache 0.19 runs a storage check (`.sccache_check` GET)
    #    when it starts its server. If that check fails, every
    #    compile fails with "Server startup failed", and
    #    SCCACHE_IGNORE_SERVER_IO_ERROR does not cover it (it only
    #    covers IO errors against a server that is already up).
    #    Measured against `cargo build -p xtask` in
    #    rust-app-template: refused endpoint rc=101 after 0 s,
    #    black-holed endpoint rc=101 after the 10 s startup timeout.
    #    SCCACHE_SKIP_CACHE_CHECK=1 is not the fix: it starts the
    #    server, but against a black hole each lookup waits out the
    #    60 s lookup timeout (646 s against 15 s).
    #
    #    So, for a compiler invocation (the first argument is not an
    #    sccache flag) with no server listening, start the server
    #    here. If that fails, run the compiler directly and leave a
    #    marker so that the next 5 minutes of rustc invocations go
    #    straight to the compiler instead of paying the startup
    #    timeout each time. A server that is already listening is
    #    trusted: once it is up, a storage error is a cache miss and
    #    the compile runs locally (sccache's own CacheReadError path).
    #    Still uncovered: Garage starting to hang after a server came
    #    up. That's slow (up to the 60 s lookup timeout per unit), and
    #    long enough to reach a job timeout. Also skipped entirely: a
    #    server on a Unix socket (SCCACHE_SERVER_UDS), which nothing
    #    here uses, because /dev/tcp can't probe one. The port is
    #    resolved the way sccache does it (commands.rs, get_addr): a
    #    value that isn't a number means 4226, so a garbage
    #    SCCACHE_SERVER_PORT can't make the probe miss a live server.
    if [ "$#" -gt 0 ] && [ "''${1#-}" = "$1" ] && [ -z "''${SCCACHE_SERVER_UDS:-}" ]; then
      port="''${SCCACHE_SERVER_PORT:-4226}"
      case "$port" in "" | *[!0-9]*) port=4226 ;; esac
      [ "''${#port}" -le 5 ] && [ "$port" -le 65535 ] || port=4226
      listening() { (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; }
      if ! listening; then
        marker="''${TMPDIR:-/tmp}/sccache-unavailable-$(${pkgs.coreutils}/bin/id -u)-$port"
        if [ -n "$(${pkgs.findutils}/bin/find "$marker" ${
      if requireCredentials
      then "-newermt '5 seconds ago'"
      else "-mmin -5"
    } 2>/dev/null)" ]; then
          exec "$@"
        fi
        if ! ${pkgs.sccache}/bin/sccache --start-server >/dev/null 2>&1 && ! listening; then
          ${pkgs.coreutils}/bin/touch "$marker" 2>/dev/null || true
          echo "sccache: cache storage unreachable, compiling locally for the next ${
      if requireCredentials
      then "5 seconds"
      else "5 minutes"
    }" >&2
          exec "$@"
        fi
        ${pkgs.coreutils}/bin/rm -f "$marker"
      fi
    fi

    exec ${pkgs.sccache}/bin/sccache "$@"
  ''
)
