# Forgejo repositories and their push mirrors.
#
#   scriptorium.repos.sabnzbd-tui = {
#     description = "TUI for SABnzbd";
#     mirrorTo = ["codeberg"];
#   };
#
# declares `forgejo_repository.sabnzbd-tui` and
# `forgejo_repository_push_mirror.sabnzbd-tui-codeberg`. Every repository gets the same
# settings: public, with pull requests, actions and issues.
#
# `mirrorTo` names entries of `scriptorium.remotes`: other hosts the forge
# pushes to over HTTPS with one account token, so a new mirror needs nothing
# set up by hand. `mirrors` is the mirror resource written out, for the cases
# that differ (an SSH mirror, whose generated key must be added on the far
# side by hand, or an address taken from another resource).
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.scriptorium;
  # `ref` does not cover providers, so the alias is spelled out.
  onForge = forge: lib.optionalAttrs (forge == "cerberus") {provider = "forgejo.cerberus";};

  # HTTPS with the account token, never SSH: Forgejo generates a key pair per
  # SSH mirror and the provider does not expose it, so each one would have to
  # be copied to the far side by hand.
  tokenMirrors = name: repo:
    lib.genAttrs repo.mirrorTo (remote: let
      inherit (cfg.remotes.${remote}) url username token;
    in {
      # A reference, so the mirror is created after the repository.
      repository = "\${forgejo_repository.${name}.name}";
      remote_address = "${url}/${name}";
      use_ssh = false;
      remote_username = username;
      remote_password = token;
    });
in {
  options.scriptorium = {
    owner = mkOption {
      type = types.str;
      default = "manjo";
      description = "The Forgejo user that owns the repositories.";
    };
    remotes = mkOption {
      default = {};
      description = "Hosts repositories are mirrored to with an account token, by name.";
      type = types.attrsOf (types.submodule {
        options = {
          url = mkOption {
            type = types.str;
            description = "Where the account's repositories live; the repository name is appended.";
            example = "https://codeberg.org/apetrovic";
          };
          username = mkOption {type = types.str;};
          token = mkOption {
            type = types.str;
            description = "The account's token, as an OpenTofu expression (`relic …`).";
          };
        };
      });
    };
    repos = mkOption {
      default = {};
      description = "Repositories, by name.";
      type = types.attrsOf (types.submodule {
        options = {
          forge = mkOption {
            type = types.enum ["noosphere" "cerberus"];
            default = "noosphere";
            description = "forge.noosphere.uk (the cluster) or forge.ugalabugala.org (cerberus).";
          };
          description = mkOption {type = types.str;};
          defaultBranch = mkOption {
            type = types.str;
            default = "master";
          };
          mirrorTo = mkOption {
            type = types.listOf (types.enum (lib.attrNames cfg.remotes));
            default = [];
            description = "`scriptorium.remotes` to push this repository to.";
          };
          mirrors = mkOption {
            type = types.attrsOf types.raw;
            default = {};
            description = ''
              Push mirrors, by suffix of the resource name. Each is the mirror
              resource itself and needs `remote_address`; the owner, repository,
              sync on commit and SSH are filled in and can be overridden.
            '';
          };
        };
      });
    };
  };

  config.resource = {
    forgejo_repository = lib.mapAttrs (name: repo:
      {
        inherit name;
        inherit (repo) description;
        private = false;
        default_branch = repo.defaultBranch;
        has_pull_requests = true;
        has_actions = true;
        has_issues = true;
      }
      // onForge repo.forge)
    cfg.repos;

    forgejo_repository_push_mirror = lib.concatMapAttrs (name: repo:
      lib.mapAttrs' (suffix: mirror:
        lib.nameValuePair "${name}-${suffix}" ({
            inherit (cfg) owner;
            repository = name;
            sync_on_commit = true;
            use_ssh = true;
          }
          // onForge repo.forge
          // mirror))
      (tokenMirrors name repo // repo.mirrors))
    cfg.repos;
  };
}
