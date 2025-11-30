{ self, ... }: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "searx";
    inherit (self.lib) mkRevProxyVHost mkDomain;

    baseDomain =
      config.clan.core.vars.generators."caddy-env".files."domain".value;

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption mkEnableOption types mkPackageOption;
    cfg = config.services.imperium.${serviceName};

  in {
    imports = [ imperiumBase ];

    options.services.imperium.${serviceName} = { };

    config = mkIf cfg.enable {};
  };
}

