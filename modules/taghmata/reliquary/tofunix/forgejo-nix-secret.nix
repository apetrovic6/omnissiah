{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-forgejo-nix-secret = {
        prompts.forgejo-token.description = "API token for cerberus Forgejo (forge.${self.lib.lab.domain}) — Settings → Applications → Generate Token";
        data.forgejo_token = "$forgejo_token";
      };
      tofunix-hermes-forgejo-password = {
        random.password = "-hex 16";
        data.password = "$password";
      };
      tofunix-hermes-forgejo-forks = {
        prompts.forgejo-token.description = "Operator-only Cerberus PAT belonging to hermes (all repositories, write:repository, read:organization, read:user)";
        data.forgejo_token = "$forgejo_token";
      };
      # advisory-bot's own PAT. tofunix forks the template with it and writes it
      # to the template's ADVISORY_PR_TOKEN secret, which the nightly advisory
      # job uses to push to that fork (rust-app-template RT-122).
      tofunix-advisory-bot-forgejo = {
        prompts.forgejo-token.description = "Cerberus PAT belonging to advisory-bot (all repositories, write:repository, read:user)";
        data.forgejo_token = "$forgejo_token";
      };
      tofunix-hermes-noosphere-password = {
        random.password = "-hex 16";
        data.password = "$password";
      };
      tofunix-hermes-noosphere-forks = {
        prompts.forgejo-token.description = "Operator-only noosphere PAT belonging to hermes (all repositories, write:repository, read:organization, read:user)";
        data.forgejo_token = "$forgejo_token";
      };
    };
  };
}
