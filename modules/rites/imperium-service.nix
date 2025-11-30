# modules/imperium.nix
{
  lib,
  pkgs,
  name,
  ...
}: let
  inherit (lib) mkOption types mkEnableOption mkPackageOption toSentenceCase;
in {
  options.services.imperium.${name} = {
    enable = mkEnableOption "Enable ${toSentenceCase name}";

    package = mkPackageOption pkgs name {};

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host/interface for ${toSentenceCase name} to bind to.";
    };

    port = mkOption {
      type = types.port;
      default = 0;
      description = "Port for ${toSentenceCase name} to listen on.";
    };

    user = mkOption {
      type = types.str;
      default = name;
      description = "User account under which ${toSentenceCase name} should run.";
    };

    group = mkOption {
      type = types.str;
      default = name;
      description = "Group under which ${toSentenceCase name} should run.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open ports in the firewall for the ${toSentenceCase name} web interface";
    };

    subdomain = mkOption {
      type = types.str;
      default = name;
      description = "Subdomain under which ${toSentenceCase name} will be exposed.";
    };

    caddy = {
      virtualHosts = mkOption {
        # virtualHosts.<vhostName>.extraConfig = "..."
        type = types.attrsOf (
          types.submodule
          ({
            name,
            vhostName,
            ...
          }: {
            options = {
              extraConfig = mkOption {
                # or types.str if you prefer
                type = types.lines;
                default = "";
                description = "Extra Caddy config for virtual host ${vhostName}.";
              };
            };
          })
        );
        default = {};
        description = "Caddy virtual hosts for ${name}.";
      };
    };
  };
}
