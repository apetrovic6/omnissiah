{self, ...}: {
  flake.nixosModules.smb-nas = {
    config,
    lib,
    pkgs,
    ...
  }: {
 clan.core.vars.generators.samba-nas-credentials = {
    # Set this to true if multiple machines should share the same creds
    share = true;

    # Generator script: build the credentials file from prompts
    script = ''
      set -eu
      {
        printf "username=%s\n" "$(cat "$prompts/username")"
        printf "password=%s\n" "$(cat "$prompts/password")"
        printf "domain=%s\n"   "$(cat "$prompts/domain")"
      } > "$out/credentials"
    '';

    runtimeInputs = [ pkgs.coreutils ];

    # What files this generator will output
    files.credentials = {
      # keep it secret, encrypted & deployed by Clan+sops
      secret = true;
      owner = "root";
      group = "root";
      mode = "0400";
      # default neededFor = "services" is fine
    };

    # Prompts you’ll see when you run `clan vars generate`
    prompts.username = {
      description = "Samba username for NAS";
      type = "line";
      persist = true;
      display.label = "NAS SMB username";
    };

    prompts.password = {
      description = "Samba password for NAS";
      type = "hidden";
      persist = true;
      display.label = "NAS SMB password";
    };

    prompts.domain = {
      description = "Samba workgroup/domain (e.g. WORKGROUP)";
      type = "line";
      persist = true;
      display.label = "NAS SMB domain";
    };
  };
    };
}
