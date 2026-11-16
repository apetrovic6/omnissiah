{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-forgejo-nix-secret = {
        prompts.forgejo-token.description = "API token for cerberus Forgejo (forge.ugalabugala.org) — Settings → Applications → Generate Token";
        data.forgejo_token = "$forgejo_token";
      };
    };
  };
}
