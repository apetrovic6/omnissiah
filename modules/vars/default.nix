{self, ...}: {
  flake.nixosModules.vars= {
    config,
    lib,
    pkgs,
    ...
  }: 
 {
  # Optional: choose where secrets go (defaults to "sops")
  clan.core.vars.settings.secretStore = "sops";

  clan.core.vars.generators.access-token = {
    # If multiple machines should share the same token, uncomment:
     share = true;

    # This declares a single secret file called "token"
    files."attic" = {
      # secret = true is the default, so this is actually optional
      secret = true;
      # You can also set owner/group/mode if a service user needs it
      owner = "apetrovic";
      # group = "some-service-group";
      # mode = "0400";
    };

    # No script / prompts: we'll set it manually with `clan vars set`
  };


 };
}
