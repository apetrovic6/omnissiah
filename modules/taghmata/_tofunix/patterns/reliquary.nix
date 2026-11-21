# Relics: clan vars read through the sops provider.
#
#   reliquary.forgejo_secrets.generator = "tofunix-forgejo-secret";
#
# declares `data.sops_file.forgejo_secrets` over that var, and
# `relic "forgejo_secrets" "forgejo_token"` is the OpenTofu expression for one
# of its keys. The vars themselves come from ../../reliquary/tofunix.
{
  config,
  lib,
  vars,
  ...
}: let
  inherit (lib) mkOption types;
in {
  options.reliquary = mkOption {
    default = {};
    description = "Shared clan vars to decrypt, by data source name.";
    type = types.attrsOf (types.submodule ({config, ...}: {
      options = {
        generator = mkOption {
          type = types.str;
          description = "The clan vars generator.";
        };
        file = mkOption {
          type = types.str;
          default = config.generator;
          description = "The generator's file; named after the generator unless set.";
        };
      };
    }));
  };

  config = {
    _module.args.relic = name: key:
      if config.reliquary ? ${name}
      then "\${data.sops_file.${name}.data[\"${key}\"]}"
      else throw "tofunix: relic `${name}` is not declared in `reliquary`";

    # Interpolating the path copies that one file to the store (cartographa/_vars.nix).
    data.sops_file =
      lib.mapAttrs (_: relic: {
        source_file =
          if builtins.pathExists (vars.shared relic.generator relic.file)
          then "${vars.shared relic.generator relic.file}"
          else throw "tofunix: the clan var `${relic.generator}` does not exist yet; run `clan vars generate <a taghmata machine> --generator ${relic.generator}` and commit vars/";
        input_type = "yaml";
      })
      config.reliquary;
  };
}
