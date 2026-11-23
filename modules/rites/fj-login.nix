# Logs `fj` (forgejo-cli) in to both forges as apetrovic, from tokens kept as
# clan vars, so a freshly deployed workstation can use `fj pr create` and
# friends without a manual `fj auth add-token` on every machine.
#
# One generator per forge, so each token can be added on its own. Create the
# token on the forge (Settings -> Applications -> Generate New Token, named
# e.g. fj-workstations; All repositories; repository and issue Read and
# Write, user Read), then
#   clan vars generate <machine> --generator fj-token-cerberus
#   clan vars generate <machine> --generator fj-token-noosphere
# Both are shared, so one prompt covers every machine that imports this
# module. An empty answer means "no token yet": the forge is skipped, and a
# deploy doesn't stop to ask again. Add or rotate it later with the same
# command plus --regenerate, deploy, and `systemctl restart fj-login` if the
# unit itself didn't change.
#
# `fj auth login` (the browser OAuth flow) can't be automated; `add-token`
# can. It refuses to replace an existing login for a host (forgejo-cli 0.7.0
# src/auth.rs), so the unit logs out first, otherwise a rotated token would
# never take effect. fj keeps the token in ~/.local/share/forgejo-cli/keys.json
# (mode 0600), the same place a manual login puts it.
{...}: let
  inherit (import ../cartographa/_cartographa.nix) lab noosphere;

  # Generator suffix -> forge host.
  forges = {
    cerberus = "forge.${lab.domain}";
    noosphere = "forge.${noosphere.domain}";
  };
  generatorName = name: "fj-token-${name}";
in {
  flake.nixosModules.fj-login = {
    config,
    lib,
    pkgs,
    ...
  }: let
    tokenFile = name: config.clan.core.vars.generators.${generatorName name}.files.token.path;
    fj = lib.getExe' pkgs.forgejo-cli "fj";
  in {
    environment.systemPackages = [pkgs.forgejo-cli];

    clan.core.vars.generators = lib.mapAttrs' (name: host:
      lib.nameValuePair (generatorName name) {
        share = true;

        prompts.token = {
          description = "Forgejo token for apetrovic on ${host} (repository + issue read/write, user read); empty = none yet";
          type = "hidden";
        };

        files.token = {
          secret = true;
          owner = "apetrovic";
          mode = "0400";
        };

        runtimeInputs = [pkgs.coreutils pkgs.gnugrep];

        script = ''
          token="$(tr -d '[:space:]' < "$prompts/token")"
          # Forgejo access tokens are 40 hex characters. A mis-paste would
          # leave fj logged in with a token every API call rejects. Empty is
          # allowed: no token for this forge yet.
          if [ -n "$token" ] && ! printf '%s' "$token" | grep -Eqx '[0-9a-f]{40}'; then
            echo "${generatorName name}: expected a 40-character hex Forgejo token for ${host} (or nothing)" >&2
            exit 1
          fi
          printf '%s' "$token" > "$out/token"
        '';
      })
    forges;

    systemd.services.fj-login = {
      description = "Log fj in to the Forgejo forges as apetrovic";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "apetrovic";
        WorkingDirectory = "~";
      };
      # A forge without a token (var not deployed yet, or left empty) is
      # skipped, and an existing manual login there is left alone.
      script = lib.concatStrings (lib.mapAttrsToList (name: host: ''
          if [ -s ${tokenFile name} ]; then
            ${fj} auth logout ${host}  # exits 0 when not logged in
            ${fj} -H ${host} auth add-token < ${tokenFile name}
          else
            echo "fj-login: no token for ${host}, skipping"
          fi
        '')
        forges);
    };
  };
}
