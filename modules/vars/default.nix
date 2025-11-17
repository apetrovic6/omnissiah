{self, ...}: {
  flake.nixosModules.vars = {
    config,
    lib,
    pkgs,
    ...
  }: {
    # Optional: choose where secrets go (defaults to "sops")
    clan.core.vars.settings.secretStore = "sops";

    clan.core.vars.generators.attic-pull-token = {
      share = true;

      files.token = {
        # secret = true is the default, so this is actually optional
        secret = true;
        # You can also set owner/group/mode if a service user needs it
        owner = "apetrovic";
        # group = "some-service-group";
        mode = "0400";
      };

      files.attic-substituter = {
        secret = true;
        owner = "apetrovic";
      };
    };
  };
}
