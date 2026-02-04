{ref, ...}: let
  # Resolve to absolute path at Nix evaluation time
in {

  imports = [ ./harbor ];

  provider.sops.default = {};


}
