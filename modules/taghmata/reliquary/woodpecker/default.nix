{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      woodpecker-default-agent-secret = {
        namespace = "woodpecker";
        random.secret = "-hex 32";
        data.WOODPECKER_DEFAULT_AGENT_SECRET = "$secret";
      };

      woodpecker-forgejo-oauth-secret = {
        namespace = "woodpecker";
        prompts.client-id = {
          description = "Enter Client ID: ";
          type = "line";
        };
        prompts.client-secret.description = "Enter Client Secret: ";
        data = {
          WOODPECKER_CLIENT_ID = "$client_id";
          WOODPECKER_CLIENT_SECRET = "$client_secret";
        };
      };
    };
  };
}
