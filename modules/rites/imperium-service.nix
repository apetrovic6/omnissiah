{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  imperiumServiceModule = { name, ... }: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable the ${name} Imperium service.";
      };

      package = mkOption {
        type = types.package;
        description = "Package providing the ${name} service.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host/interface for ${name} to bind to.";
      };

      port = mkOption {
        type = types.port;
        default = 0;
        description = "Port for ${name} to listen on.";
      };

      user = mkOption {
        type = types.str;
        default = "services";
        description = "User account under which ${name} should run.";
      };

      group = mkOption {
        type = types.str;
        default = "services";
        description = "Group under which ${name} should run.";
      };

      subDomain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional subdomain for ${name}, e.g. "audiobookshelf" for
          audiobookshelf.${config.networking.domain}.
        '';
      };
    };
  };
in {
  options.services.imperium = mkOption {
    type = types.attrsOf (types.submodule imperiumServiceModule);
    default = {};
    description = "Imperium generic wrapper for self-hosted services.";
  };
}
