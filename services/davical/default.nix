# davical-go — CalDAV/CardDAV server (Go rewrite of DAViCal)
#
# Built purely from source with Nix: no Dockerfile, no external base image, no
# `pullImage`. The binaries are static, so the container image is the Nix store
# subtree plus a CA bundle (see image.nix).
#
#   nix build .#davical-go     # davicald, davical-admin, davical-cron, cfg2env
#   nix build .#davical-image  # docker/podman image tarball
#
# See README.md for the manual deployment steps (schema bootstrap, first user,
# cron, reverse proxy).
{
  pkgs,
  lib ? pkgs.lib,
}: let
  davical-go = pkgs.callPackage ./package.nix {};
in {
  inherit davical-go;

  # The package itself (davicald + davical-admin + davical-cron + cfg2env).
  package = davical-go;

  # `docker load < $(nix build .#davical-image)` — or pipe it straight in with
  # pkgs.davical-go-image.stream.
  image = pkgs.callPackage ./image.nix {inherit davical-go;};
}
