# davical-go: CalDAV/CardDAV server (Go rewrite of DAViCal), built purely
# from source with Nix -- see services/davical/README.md.
{...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    davical = import ../../services/davical {inherit pkgs lib;};
  in {
    packages.davical-go = davical.package;
    packages.davical-go-image = davical.image;
  };
}
