{...}: {
  flake.nixosModules.hermes-forgejo-bot = {pkgs, ...}: {
    clan.core.vars.generators = {
      # This key authenticates to Forgejo, not from ryza into stygies.
      hermes-forgejo-ssh = {
        files."id_ed25519" = {
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };
        files."id_ed25519.pub".secret = false;

        runtimeInputs = [pkgs.openssh];
        script = ''
          ssh-keygen -q -t ed25519 -N "" -C hermes@stygies -f "$out/id_ed25519"
        '';
      };

      hermes-forgejo-token = {
        prompts.token = {
          description = "Hermes Forgejo token for manjo/rust-app-template and manjo/pilot (write:repository, write:issue)";
          type = "hidden";
        };
        files.token = {
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };

        runtimeInputs = [pkgs.coreutils];
        script = ''
          cp "$prompts/token" "$out/token"
        '';
      };
    };
  };
}
