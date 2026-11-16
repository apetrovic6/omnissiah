{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-pocketid-secret = {
        prompts.api-key.description = "PocketId API token (Settings -> Administration -> API Keys)";
        data.api_key = "$api_key";
      };

      tofunix-pocketid-lu = {
        file = "tofunix-pocketid-secret";
        prompts = {
          username = {
            description = "Username";
            type = "line";
          };
          email = {
            description = "Email";
            type = "line";
          };
          first-name = {
            description = "First Name:";
            type = "line";
          };
          last-name = {
            description = "Last Name:";
            type = "line";
          };
        };
        data = {
          username = "$username";
          email = "$email";
          first_name = "$first_name";
          last_name = "$last_name";
        };
      };
    };
  };
}
