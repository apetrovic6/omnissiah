{self, ...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    serviceName = "caddy";

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption types toSentenceCase;
    cfg = config.services.imperium.${serviceName};
    caddyVars = config.clan.core.vars.generators.caddy-env;
  in {
    imports = [imperiumBase];

    options.services.imperium.${serviceName} = {
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/caddy";
        description = ''
          The data directory for ${toSentenceCase serviceName}.

          ::: {.note}
          If left as the default value this directory will automatically be created
          before the ${toSentenceCase serviceName}server starts, otherwise you are responsible for ensuring
          the directory exists with appropriate ownership and permissions.

          Caddy v2 replaced `CADDYPATH` with XDG directories.
          See <https://caddyserver.com/docs/conventions#file-locations>.
          :::
        '';
      };

      logDir = mkOption {
        type = types.path;
        default = "/var/log/caddy";
        description = ''
          Directory for storing ${toSentenceCase serviceName} access logs.

          ::: {.note}
          If left as the default value this directory will automatically be created
          before the ${toSentenceCase serviceName} server starts, otherwise the sysadmin is responsible for
          ensuring the directory exists with appropriate ownership and permissions.
          :::
        '';
      };
    };

    config = mkIf cfg.enable {
      services.caddy = {
        enable = true;
        package = cfg.package;
        user = cfg.user;
        group = cfg.group;
        virtualHosts = cfg.caddy.virtualHosts;
        environmentFile = caddyVars.files."caddy.env".path;
      };
      systemd.services."caddy".serviceConfig = {
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      };

      #### 1. Clan vars generator for domain + IP + token -> env file ####
      clan.core.vars.generators.caddy-env = {
        # Set to true if you want the same domain/IP/token shared across machines
        share = true;

        # Files this generator will output
        files."caddy.env" = {
          secret = true; # contains the token -> keep it secret
          owner = config.services.caddy.user;
          group = config.services.caddy.group;
          mode = "0400";
        };

        # Optional: separate non-secret files for domain/ip
        files."domain" = {secret = false;};
        files."ip" = {secret = false;};

        # Prompts that clan will ask you for
        prompts.domain = {
          description = "Base domain for Caddy (e.g. example.com)";
          type = "line";
          persist = true;
        };

        prompts.ip = {
          description = "Public IP address for DNS (A record)";
          type = "line";
          persist = true;
        };

        prompts.token = {
          description = "Cloudflare API token for Caddy DNS-01";
          type = "hidden";
          persist = true;
        };

        runtimeInputs = [pkgs.coreutils];

        script = ''
                set -eu

                domain="$(cat "$prompts/domain")"
                ip="$(cat "$prompts/ip")"
                token="$(cat "$prompts/token")"

                # Non-secret helpers usable from Nix if you want
                echo "$domain" > "$out/domain"
                echo "$ip"     > "$out/ip"

                # Env file that Caddy will read
                cat > "$out/caddy.env" <<EOF
          LAB_DOMAIN=$domain
          LAB_IP=$ip
          CLOUDFLARE_API_TOKEN=$token
          EOF
        '';
      };
    };
  };
}
