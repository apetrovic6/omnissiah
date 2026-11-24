# Hermes forge transports and the app/Matrix project allowlist.
let
  inherit (import ../../modules/cartographa/_cartographa.nix) lab noosphere;

  forges = {
    cerberus = rec {
      host = "forge.${lab.domain}";
      sshPort = 2222;
      gitBase = "ssh://forgejo@${host}:${toString sshPort}";
      tokenGenerator = "hermes-forgejo-token";
      botEnabled = true;
    };
    noosphere = rec {
      host = "forge.${noosphere.domain}";
      gitBase = "https://${host}";
      tokenGenerator = "hermes-forgejo-noosphere-token";
      # Off until the bot's account and runtime PAT exist (README, "Hermes on
      # noosphere Forgejo"). While false, no clan var is declared for it, so
      # no deploy prompts for the PAT, and no Hermes tooling touches this host.
      botEnabled = true;
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

  # A project on a forge whose bot is off would be routed to a host Hermes has
  # no credentials for; fail the evaluation instead.
  disabled = builtins.filter (name: !(forges.${projects.${name}.forge}.botEnabled or false)) (builtins.attrNames projects);
in {
  inherit forges;
  projects =
    if disabled == []
    then projects
    else throw "machines/ryza/_coder-projects.nix: project(s) ${builtins.concatStringsSep ", " disabled} use a forge with botEnabled = false. Finish the bot account and PAT steps in the README, then set botEnabled = true for that forge in the same commit as its PAT var.";
}
