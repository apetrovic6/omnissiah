# Database credentials for the yarr apps, one SopsSecret each. They share the
# pg-yarr CNPG cluster, which reloads a role's password when its Secret changes
# (the cnpg.io/reload label).
{
  self,
  lib,
  ...
}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs (lib.listToAttrs (map (app:
      lib.nameValuePair "pg-${app}-sopssecret" {
        namespace = "yarr";
        secretName = "pg-${app}-password";
        labels."cnpg.io/reload" = "true";
        prompts."pg-${app}-username" = {
          description = "DB Username";
          type = "line";
          var = "username";
        };
        prompts."pg-${app}-password" = {
          description = "DB Password";
          var = "password";
        };
        data = {
          username = "$username";
          password = "$password";
        };
      }) ["lidarr" "prowlarr" "radarr" "seerr" "sonarr"]));
  };
}
