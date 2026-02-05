{ref, ...}: let
  noosphere = import ../../../../vars/_noosphere-values.nix;
  inherit (noosphere) domain;
in {}
