{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "searx";
    inherit (self.lib) mkRevProxyVHost mkDomain;

    searxngFile =
      config.clan.core.vars.generators."searxng-secret-key".files."env".path;

    baseDomain =
      config.clan.core.vars.generators."caddy-env".files."domain".value;

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption mkEnableOption types mkPackageOption;
    cfg = config.services.imperium.${serviceName};
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {};

    config = mkIf cfg.enable {
      services.searx = {
        enable = true;
        package = cfg.package;
        limiterSettings = {
          real_ip = {
            x_for = 1;
            ipv4_prefix = 32;
            ipv6_prefix = 56;
          };
          trusted_proxies = ["100.0.0.0/24"];
          botdetection.ip_lists.block_ip = [
          ];
        };
        settings = {
          server.port = cfg.port;
          server.bind_address = cfg.host;
          server.secret_key = "@SEARX_SECRET_KEY@";
        };

        environmentFile = searxngFile;
      };

      services.caddy.virtualHosts = {
        "${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost cfg.port;
        };
      };

      clan.core.vars.generators."searxng-secret-key" = {
        # set to true if you want the same key shared across machines
        share = false;

        runtimeInputs = [pkgs.coreutils pkgs.openssl];

        # raw key (just the secret, no KEY= prefix)
        files."key" = {
          secret = true;
          owner = cfg.user; # or "root" or the service user you want
          group = cfg.group;
          mode = "0400";
        };

        # env-style file, e.g. SECRET_KEY=...
        files."env" = {
          secret = true;
          owner = cfg.user; # or "root" or the service user you want
          group = cfg.group;
          mode = "0400";
        };

        # no prompts: it auto-generates on first `clan vars generate`
        script = ''
                  set -eu

                  key="$(openssl rand -hex 32)"

                  # raw key
                  printf '%s\n' "$key" > "$out/key"

                  # env file, good for EnvironmentFile=...
                  cat > "$out/env" <<EOF
          SEARXNG_SECRET_KEY=$key
          EOF
        '';
      };
    };
  };
}
