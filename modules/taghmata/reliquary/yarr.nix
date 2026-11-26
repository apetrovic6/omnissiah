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
      }) ["lidarr" "prowlarr" "radarr" "seerr" "sonarr"])
      // {
        # Nothing to type in: the role is always `bazarr` and the password is
        # generated. Hex so it needs no escaping anywhere it ends up.
        pg-bazarr-sopssecret = {
          namespace = "yarr";
          secretName = "pg-bazarr-password";
          labels."cnpg.io/reload" = "true";
          random.password = "-hex 32";
          data = {
            username = "bazarr";
            password = "$password";
          };
        };
      });
  };
}
