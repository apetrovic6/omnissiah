{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-s3-secrets = {
        prompts.access-key-id = {
          description = "S3 access key ID for the opentofu Garage bucket";
          type = "line";
        };
        prompts.secret-access-key.description = "S3 secret access key for the opentofu Garage bucket";
        data = {
          access_key_id = "$access_key_id";
          secret_access_key = "$secret_access_key";
        };
      };
    };
  };
}
