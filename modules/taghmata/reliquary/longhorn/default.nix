{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      s3-longhorn-backup = {
        namespace = "longhorn-system";
        secretName = "s3-backup-secret";
        prompts.access-key-id = {
          description = "Enter Access Key ID: ";
          type = "line";
          var = "access_key";
        };
        prompts.access-key-secret = {
          description = "Enter Access Key Secret: ";
          var = "secret_key";
        };
        prompts.endpoint = {
          description = "Enter s3 endpoint: ";
          type = "line";
        };
        data = {
          AWS_ACCESS_KEY_ID = "$access_key";
          AWS_SECRET_ACCESS_KEY = "$secret_key";
          AWS_ENDPOINTS = "$endpoint";
        };
      };
    };
  };
}
