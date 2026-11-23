# Logs `fj` (forgejo-cli) in to both forges as apetrovic, from tokens kept as
# a clan var, so a freshly deployed workstation can use `fj pr create` and
# friends without a manual `fj auth add-token` on every machine.
#
# Create one token per forge (Settings -> Applications -> Generate New Token;
# scopes: repository and issue Read and Write, user Read), then
#   clan vars generate <machine> --generator fj-tokens
# (shared, so one prompt covers every machine that imports this module). To
# rotate a token: `clan vars generate <machine> --generator fj-tokens
# --regenerate`, deploy, and `systemctl restart fj-login` if the unit itself
# didn't change.
#
# `fj auth login` (the browser OAuth flow) can't be automated; `add-token`
# can. It refuses to replace an existing login for a host (forgejo-cli 0.7.0
# src/auth.rs), so the unit logs out first, otherwise a rotated token would
# never take effect. fj keeps the token in ~/.local/share/forgejo-cli/keys.json
# (mode 0600), the same place a manual login puts it.
{...}: let
  inherit (import ../cartographa/_cartographa.nix) lab noosphere;

  # Prompt and file name -> forge host.
  forges = {
    cerberus = "forge.${lab.domain}";
    noosphere = "forge.${noosphere.domain}";
  };
in {
  flake.nixosModules.fj-login = {
    config,
    lib,
    pkgs,
    ...
  }: let
    generator = config.clan.core.vars.generators.fj-tokens;
    fj = lib.getExe' pkgs.forgejo-cli "fj";
  in {
    environment.systemPackages = [pkgs.forgejo-cli];

    clan.core.vars.generators.fj-tokens = {
      share = true;

      prompts = lib.mapAttrs (name: host: {
        description = "Forgejo token for apetrovic on ${host} (repository + issue read/write, user read)";
        type = "hidden";
        persist = false;
      }) forges;

      files = lib.mapAttrs (_: _: {
        secret = true;
        owner = "apetrovic";
        mode = "0400";
      }) forges;

      runtimeInputs = [pkgs.coreutils pkgs.gnugrep];

      script = lib.concatStrings (lib.mapAttrsToList (name: host: ''
          token="$(tr -d '[:space:]' < "$prompts/${name}")"
          # Forgejo access tokens are 40 hex characters. A mis-paste would
          # leave fj logged in with a token every API call rejects.
          if ! printf '%s' "$token" | grep -Eqx '[0-9a-f]{40}'; then
            echo "fj-tokens: ${name} (${host}): expected a 40-character hex Forgejo token" >&2
            exit 1
          fi
          printf '%s' "$token" > "$out/${name}"
        '')
        forges);
    };

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
      # A forge whose token isn't deployed yet is skipped, not an error: the
      # other one still gets logged in.
      script = lib.concatStrings (lib.mapAttrsToList (name: host: ''
          if [ -r ${generator.files.${name}.path} ]; then
            ${fj} auth logout ${host}  # exits 0 when not logged in
            ${fj} -H ${host} auth add-token < ${generator.files.${name}.path}
          else
            echo "fj-login: no token for ${host} yet, skipping"
          fi
        '')
        forges);
    };
  };
}
