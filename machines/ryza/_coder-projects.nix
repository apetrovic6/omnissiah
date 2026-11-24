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
      # Needs the bot's account and runtime PAT (README, "Hermes on noosphere
      # Forgejo"). While false, no clan var is declared for it, so no deploy
      # prompts for the PAT, and no Hermes tooling touches this host.
      botEnabled = true;
    };
  };

  # `owner` is the upstream repo's owner (user or org); it defaults to
  # manjo. Hermes forks it to hermes/<repo> and opens PRs into it.
  projects = {
    tally = {
      forge = "noosphere";
      owner = "monolith-softworks";
      room = "!vR9D2BaWBsjdrDlBt6Vb7_iEKpj4iEny5tRPOnzVUv0";
    };
    rust-app-template = {
      forge = "cerberus";
      room = "!qfeHKyEuU37YpF4mms2eyiISUIbyx8ajidvKeQn3b-c";
    };
  };

  # The owner lands in Git URLs and fj arguments, and hermes owns the forks.
  badOwner = builtins.filter (name: let
    owner = projects.${name}.owner or "manjo";
  in
    owner == "hermes" || builtins.match "[A-Za-z0-9][A-Za-z0-9._-]*" owner == null) (builtins.attrNames projects);
  # A project on a forge whose bot is off would be routed to a host Hermes has
  # no credentials for; fail the evaluation instead.
  disabled = builtins.filter (name: !(forges.${projects.${name}.forge}.botEnabled or false)) (builtins.attrNames projects);
in {
  inherit forges;
  projects =
    if badOwner != []
    then throw "machines/ryza/_coder-projects.nix: project(s) ${builtins.concatStringsSep ", " badOwner} have an invalid owner: it must be a plain user or org name, never hermes (the fork owner)."
    else if disabled == []
    then projects
    else throw "machines/ryza/_coder-projects.nix: project(s) ${builtins.concatStringsSep ", " disabled} use a forge with botEnabled = false. Finish the bot account and PAT steps in the README, then set botEnabled = true for that forge in the same commit as its PAT var.";
}
