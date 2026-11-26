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
  # manjo. Hermes forks it to hermes/<repo> and opens PRs into it. `room` is
  # the project's Matrix room ID; leave it out (or null) for an app-only
  # project, which Hermes takes only from the app, never from Matrix.
  projects = {
    tally = {
      forge = "noosphere";
      owner = "monolith-softworks";
      room = "!vR9D2BaWBsjdrDlBt6Vb7_iEKpj4iEny5tRPOnzVUv0";
    };
    inanna = {
      forge = "noosphere";
      owner = "monolith-softworks";
      room = "!7QOQWeDhddbtgBqxsYPhfNj2rsUePiB2iTeWEiYe010";
    };
    auspex = {
      forge = "noosphere";
      room = "!zq6JSOK1G2Ed96ayYGRGIO5T9c83IgwPQitzkkaI6dk";
    };
    mushroom-farmer = {
      forge = "noosphere";
      room = "!NjnL0nBC6h_twl-qhOsjeDllIKpgn0WRDGs5tzVZB_E";
    };
    rust-app-template = {
      forge = "cerberus";
      room = "!qfeHKyEuU37YpF4mms2eyiISUIbyx8ajidvKeQn3b-c";
    };
  };

  # A function, so checks can run it on other values (the `coderProjects`
  # options in machines/ryza/hermes.nix and hermes-forgejo-bot.nix).
  check = projects: let
    names = builtins.attrNames projects;
    # The owner lands in Git URLs and fj arguments, and hermes owns the forks.
    badOwner = builtins.filter (name: let
      owner = projects.${name}.owner or "manjo";
    in
      owner == "hermes" || builtins.match "[A-Za-z0-9][A-Za-z0-9._-]*" owner == null)
    names;
    # A project on a forge whose bot is off would be routed to a host Hermes has
    # no credentials for; fail the evaluation instead.
    disabled = builtins.filter (name: !(forges.${projects.${name}.forge}.botEnabled or false)) names;
    room = name: projects.${name}.room or null;
    roomed = builtins.filter (name: room name != null) names;
    # "" is not "no room": leave `room` out (or null) for an app-only project.
    badRoom = builtins.filter (name: !(builtins.isString (room name)) || builtins.match "![^[:space:]]+" (room name) == null) roomed;
    # Each room is one conversation, so two projects can't share it.
    sharedRoom = builtins.filter (name: builtins.length (builtins.filter (other: room other == room name) roomed) > 1) roomed;
  in
    if badOwner != []
    then throw "machines/ryza/_coder-projects.nix: project(s) ${builtins.concatStringsSep ", " badOwner} have an invalid owner: it must be a plain user or org name, never hermes (the fork owner)."
    else if badRoom != []
    then throw "machines/ryza/_coder-projects.nix: project(s) ${builtins.concatStringsSep ", " badRoom} have an invalid room: use the room's internal ID (\"!…\"), or leave `room` out for an app-only project."
    else if sharedRoom != []
    then throw "machines/ryza/_coder-projects.nix: project(s) ${builtins.concatStringsSep ", " sharedRoom} share a Matrix room; give each project its own room, or none for an app-only project."
    else if disabled == []
    then projects
    else throw "machines/ryza/_coder-projects.nix: project(s) ${builtins.concatStringsSep ", " disabled} use a forge with botEnabled = false. Finish the bot account and PAT steps in the README, then set botEnabled = true for that forge in the same commit as its PAT var.";
in {
  inherit forges check;
  projects = check projects;
}
