{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-forgejo-secret = {
        prompts.forgejo-token.description = "Forgejo API token (Settings -> Applications -> Generate Token)";
        data.forgejo_token = "$forgejo_token";
      };
    };
  };
}
