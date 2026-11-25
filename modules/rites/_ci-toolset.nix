# What every Forgejo CI job finds on its PATH, besides nix itself (each side
# adds its own config.nix.package): the persistent host runners
# (forgejo-runner.nix hostPackages) and the nix-eph slot guest
# (forgejo-runner-ephemeral.nix, which asserts its PATH carries all of these).
#
# EVERY RUNNER CARRYING A LABEL MUST BE ABLE TO RUN EVERY JOB ON IT (top of
# forgejo-runner.nix), so the list lives in one place. The order is the PATH
# order, which is part of every unit that uses it: append, don't sort.
pkgs:
with pkgs; [
  bash
  coreutils
  gnutar
  gzip
  git
  # Host steps outside a devenv shell had no `diff` (fishing's and
  # rust-app-template's reported `diff: command not found`), and
  # rust-app-template ended up parsing JSON with grep. Shared list, not
  # extraHostPackages: every runner carries `nix:host`, so a tool on one
  # machine alone fails those jobs at random.
  diffutils
  jq
  # actions/checkout runs on node.
  nodejs
  devenv
  cacert
  mold
  # For steps that run cargo outside a devenv shell.
  cargo
  rustc
  gawk
  # cargo needs a linker for build scripts (proc-macro2, libc, ...). Without
  # it every build script fails with `linker 'cc' not found`. This wrapper
  # provides cc/gcc/ld.
  stdenv.cc
]
