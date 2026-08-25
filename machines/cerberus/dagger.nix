# Dagger engine — the build runtime for the Forgejo Actions CI pipeline in the
# `fishing` repo (the `ci` crate, driven by dagger-sdk).
#
# Why a long-lived container instead of letting the dagger CLI provision one
# per run: the runner service is DynamicUser=true (see the generated
# gitea-runner-cerberus.service), so its UID is ephemeral. That rules out
# rootless podman for the runner — no stable subuid range, no lingering
# session, no persistent build cache between jobs.
#
# Why TCP instead of the default unix socket: the usual `docker-container://`
# scheme makes the CLI `docker exec` into the engine container, which a
# DynamicUser cannot do against a root-owned container. Listening on host
# loopback means the runner needs no container-runtime access at all — it only
# opens a TCP connection. (`podman-container://` is not an option: dagger
# v0.21.8 rejects it with `no driver for scheme "podman-container" found`.)
{...}: let
  # MUST match the engine version dagger-sdk pins in the fishing repo
  # (ci/Cargo.toml -> dagger-sdk 0.21.8) and the dagger CLI on PATH below.
  # All three move together or sessions fail to start.
  version = "v0.21.8";
  port = 8080;
in {
  virtualisation.oci-containers.containers.dagger-engine = {
    image = "registry.dagger.io/engine:${version}";
    autoStart = true;

    # buildkit needs full privileges to set up mounts and namespaces.
    extraOptions = [
      "--privileged"
      # Public DNS points forge.ugalabugala.org at the VPS, so image pushes
      # from inside the engine would hairpin out to the internet and back
      # through Pangolin. Same reason nopresh.nix pins it via networking.hosts
      # on the host — but that file does not reach into a container netns.
      "--add-host=forge.ugalabugala.org:192.168.1.105"
    ];

    # Bound to host loopback only. The engine speaks an unauthenticated
    # protocol, so it must never be exposed beyond 127.0.0.1.
    ports = ["127.0.0.1:${toString port}:${toString port}"];
    cmd = ["--addr" "tcp://0.0.0.0:${toString port}"];

    # Build cache. Worth persisting: without it every job recompiles the whole
    # dependency tree, which is most of the pipeline's runtime.
    volumes = ["dagger-engine-state:/var/lib/dagger"];

    # Deliberately NO io.containers.autoupdate label. podman-auto-update runs
    # daily on this host (see nopresh.nix); letting it bump the engine would
    # silently break the exact-version match with dagger-sdk.
  };
}
