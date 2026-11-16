{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      forgejo-admin-secret = {
        namespace = "forgejo";
        prompts.username = {
          description = "Enter Forgejo Admin Username: ";
          type = "line";
        };
        prompts.password.description = "Enter Forgejo Admin Password: ";
        data = {
          username = "$username";
          password = "$password";
        };
      };

      forgejo-keycloak-oauth-secret = {
        namespace = "forgejo";
        prompts.key = {
          description = "Enter Access Key ID: ";
          type = "line";
        };
        prompts.secret.description = "Enter Access Key Secret: ";
        data = {
          key = "$key";
          secret = "$secret";
        };
      };
    };
  };
}
