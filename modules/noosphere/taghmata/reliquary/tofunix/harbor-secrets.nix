{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-harbor-secrets = {
        prompts.harbor-username = {
          description = "Harbor robot account username (e.g., robot$opentofu)";
          type = "line";
        };
        prompts.harbor-password.description = "Harbor robot account password";
        data = {
          harbor_username = "$harbor_username";
          harbor_password = "$harbor_password";
        };
      };
    };
  };
}
