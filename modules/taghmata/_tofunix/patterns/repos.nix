# Forgejo repositories and their push mirrors.
#
#   scriptorium.repos.sabnzbd-tui = {
#     description = "TUI for SABnzbd";
#     mirrors.github.remote_address = "https://github.com/apetrovic6/sabnzbd-tui";
#   };
#
# declares `forgejo_repository.sabnzbd-tui` and
# `forgejo_repository_push_mirror.sabnzbd-tui-github`. Every repository gets the same
# settings: public, with pull requests, actions and issues.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  inherit (import ../../../cartographa/_cartographa.nix) lab;
  cfg = config.scriptorium;
  # `ref` does not cover providers, so the alias is spelled out.
  onForge = forge: lib.optionalAttrs (forge == "cerberus") {provider = "forgejo.cerberus";};
in {
  options.scriptorium = {
    owner = mkOption {
      type = types.str;
      default = "manjo";
      description = "The Forgejo user that owns the repositories.";
    };
    repos = mkOption {
      default = {};
      description = "Repositories, by name.";
      type = types.attrsOf (types.submodule {
        options = {
          forge = mkOption {
            type = types.enum ["noosphere" "cerberus"];
            default = "noosphere";
            description = "forge.noosphere.uk (the cluster) or forge.${lab.domain} (cerberus).";
          };
          description = mkOption {type = types.str;};
          defaultBranch = mkOption {
            type = types.str;
            default = "master";
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
      repo.mirrors)
    cfg.repos;
  };
}
