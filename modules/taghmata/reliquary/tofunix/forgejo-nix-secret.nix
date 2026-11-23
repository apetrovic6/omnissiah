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
    };
  };
}
