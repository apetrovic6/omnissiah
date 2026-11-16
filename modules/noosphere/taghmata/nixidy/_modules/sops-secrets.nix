# `sopsSecrets`, an option of every application: the cluster secrets it ships.
#
#   applications.bytestash.sopsSecrets = ["bytestash-jwt-secret"];
#
# Each name is a clan vars generator from taghmata/reliquary whose output file
# has the same name: a sops-encrypted SopsSecret manifest that
# sops-secrets-operator turns into a Secret in the cluster. Listing it here
# adds that manifest to the application, which is what
#
#   yamls = [(builtins.readFile (vars.shared "bytestash-jwt-secret" "bytestash-jwt-secret"))];
#
# did by hand. For a generator whose file is named differently, give both:
# `{ generator = "ntfy-access"; file = "alertmanager-ntfy"; }`.
{vars}: {
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types;
in {
  options.sopsSecrets = mkOption {
    type = types.listOf (types.either types.str (types.submodule {
      options = {
        generator = mkOption {
          type = types.str;
          description = "Name of the clan vars generator.";
        };
        file = mkOption {
          type = types.str;
          description = "Name of the generator's output file.";
        };
      };
    }));
    default = [];
    description = "Sops-encrypted SopsSecret manifests from the clan vars store to include in this application.";
  };

  config.yamls =
    map (
      secret:
        builtins.readFile (
          if builtins.isString secret
          then vars.shared secret secret
          else vars.shared secret.generator secret.file
        )
    )
    config.sopsSecrets;
}
