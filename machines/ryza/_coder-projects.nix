# Hermes forge transports and the app/Matrix project allowlist.
let
  inherit (import ../../modules/cartographa/_cartographa.nix) lab noosphere;
in {
  forges = {
    cerberus = rec {
      host = "forge.${lab.domain}";
      sshPort = 2222;
      gitBase = "ssh://forgejo@${host}:${toString sshPort}";
      tokenGenerator = "hermes-forgejo-token";
    };
    noosphere = rec {
      host = "forge.${noosphere.domain}";
      gitBase = "https://${host}";
      tokenGenerator = "hermes-forgejo-noosphere-token";
    };
  };
  projects = {
    tally = {
      forge = "cerberus";
      room = "!vR9D2BaWBsjdrDlBt6Vb7_iEKpj4iEny5tRPOnzVUv0";
    };
    rust-app-template = {
      forge = "cerberus";
      room = "!qfeHKyEuU37YpF4mms2eyiISUIbyx8ajidvKeQn3b-c";
    };
  };
}
