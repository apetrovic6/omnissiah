{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      karakeep-meilisearch-secret = {
        namespace = "karakeep";
        random.secret = "-base64 36";
        data.MEILI_MASTER_KEY = "$secret";
      };

      karakeep-secret = {
        namespace = "karakeep";
        random = {
          secret = "-base64 36";
          nextpublicsecret = "-base64 36";
        };
        data = {
          NEXTAUTH_SECRET = "$secret";
          NEXT_PUBLIC_SECRET = "$nextpublicsecret";
        };
      };

      karakeep-sso-secret = {
        namespace = "karakeep";
        prompts.client-id = {
          description = "Client ID";
          type = "line";
        };
        prompts.client-secret.description = "Client Secret";
        data = {
          OAUTH_CLIENT_ID = "$client_id";
          OAUTH_CLIENT_SECRET = "$client_secret";
        };
      };
    };
  };
}
