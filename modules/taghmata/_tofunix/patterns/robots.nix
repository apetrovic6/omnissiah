# Harbor robot accounts that push and pull images.
#
#   scriptorium.robots.woodpecker = {
#     description = "Robot account for Woodpecker CI";
#     secret = relic "woodpecker_secrets" "woodpecker_password";
#   };
#
# Pull is always granted with push: skopeo checks for existing blobs first.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
in {
  options.scriptorium.robots = mkOption {
    default = {};
    description = "Robot accounts, by name.";
    type = types.attrsOf (types.submodule {
      options = {
        description = mkOption {type = types.str;};
        secret = mkOption {
          type = types.str;
          description = "The robot's secret, as an OpenTofu expression (`relic …`).";
        };
        project = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "The one project it may use; every project when null.";
        };
      };
    });
  };

  config.resource.harbor_robot_account =
    lib.mapAttrs (name: robot: {
      inherit name;
      inherit (robot) description secret;
      level =
        if robot.project == null
        then "system"
        else "project";
      permissions = [
        {
          access = [
            {
              action = "push";
              resource = "repository";
            }
            {
              action = "pull";
              resource = "repository";
            }
          ];
          kind = "project";
          namespace =
            if robot.project == null
            then "*"
            else robot.project;
        }
      ];
    })
    config.scriptorium.robots;
}
