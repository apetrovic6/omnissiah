# Harbor robot accounts that push and pull images.
#
#   scriptorium.robots."<name>-ci" = {
#     description = "CI push for <name>";
#     secret = relic "robot_<name>" "robot_secret";
#     project = "<harbor-project>";
#   };
#
# Pull is always granted with push: skopeo checks for existing blobs first.
#
# The secret goes in as `secret_wo`, a write-only attribute: OpenTofu sends
# it to Harbor but never records it on the resource. Write-only values are
# only sent when `secret_wo_version` changes, so after rotating a robot's
# secret, bump its `secretVersion` too, or Harbor keeps the old one. (The
# value still reaches the state through the `data.sops_file` it is read
# from; this only keeps it off the robot resource.)
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
        secretVersion = mkOption {
          type = types.ints.positive;
          default = 1;
          description = "Bump to send `secret` to Harbor again, e.g. after rotating it.";
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
      inherit (robot) description;
      secret_wo = robot.secret;
      secret_wo_version = robot.secretVersion;
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
