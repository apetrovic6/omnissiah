# The CI upload credentials: the key that signs what CI builds, and the netrc
# for ncps' /upload. Declared only on machines that upload, because whatever
# declares a generator gets its secret deployed: the persistent runners
# (forgejo-runner.nix) and trusted nix-eph jobs (_forgejo-ephemeral-trusted.nix)
# set `enable`.
#
# CI signing key, shared by every machine that uploads. ncps (taghmata nixidy
# apps/scriptorium/ncps) accepts a PUT only when the narinfo carries this key's
# signature, so it doubles as the upload credential. Separate from ncps' own
# serving key: a leaked CI key can push into the cache, but cannot forge ncps'
# signature on upstream paths. ncps reads the public key straight from
# vars/shared/${generator}, so renaming the generator means updating that path
# too.
#
# Basic auth on /upload: the `ncps-upload-auth` generator lives with the
# Traefik side in taghmata/reliquary/ncps (nixosModules.reliquary-ncps), which
# this module imports. Only the push hooks get the netrc, not nix as a whole.
{self, ...}: let
  generator = "nix-ci-signing-key";
  # `<name>-<n>`: bump the suffix to rotate while the old key is still trusted.
  ciKeyName = "ci.noosphere.uk-1";
in {
  flake.nixosModules.ci-credentials = {
    # More than one module imports this on the same machine (ryza: the
    # persistent runner and nix-eph). With a key, the module system loads it
    # once; without one, its options would be declared twice.
    key = "omnissiah#nixosModules.ci-credentials";
    imports = [
      self.nixosModules.reliquary-ncps
      ({
        config,
        lib,
        pkgs,
        ...
      }: let
        cfg = config.services.imperium.ciCredentials;
        gens = config.clan.core.vars.generators;
      in {
        options.services.imperium.ciCredentials = {
          # reliquary-ncps declares the netrc wherever this module is imported.
          enable = lib.mkEnableOption "the CI signing key on this machine";
          signingKey = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = gens.${generator}.files."key".path;
            defaultText = lib.literalExpression ''config.clan.core.vars.generators.${generator}.files."key".path'';
            description = "Deployed path of the CI signing key. Root-only; read it through systemd LoadCredential.";
          };
          ncpsNetrc = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = gens.ncps-upload-auth.files.netrc.path;
            defaultText = lib.literalExpression "config.clan.core.vars.generators.ncps-upload-auth.files.netrc.path";
            description = "Deployed path of the netrc for ncps' /upload. Root-only, like the key.";
          };
        };

        config = lib.mkIf cfg.enable {
          clan.core.vars.generators.${generator} = {
            share = true;
            files."key".secret = true;
            files."key.pub".secret = false;
            runtimeInputs = [pkgs.nix];
            script = ''
              nix-store --generate-binary-cache-key ${ciKeyName} "$out/key" "$out/key.pub"
            '';
          };
        };
      })
    ];
  };
}
