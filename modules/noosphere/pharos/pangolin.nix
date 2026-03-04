{config, ...}: let
in {
  flake.nixosModules.pharos = {pkgs, lib, config, ...}: let
    geolite2-country-db = pkgs.runCommand "geolite2-country-db" {} ''
      mkdir -p $out
      tar xzf ${pkgs.fetchurl {
        url = "https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/GeoLite2-Country.tar.gz";
        hash = "sha256-61uX4tElLST7YMgtwyDp1e3y1DTpP8mUKmN5VlTh25Q=";
      }} --strip-components=1
      cp GeoLite2-Country.mmdb $out/
    '';
  in {
    services.pangolin.settings.server.maxmind_db_path = lib.mkIf (config.services.pangolin.enable or false) "${geolite2-country-db}/GeoLite2-Country.mmdb";

    clan.core.vars.generators.pangolin = lib.mkIf (config.services.pangolin.enable or false) {
      files."pangolin.env" = {
        secret = true;
        mode = "0400";
      };

      # Raw DB password consumed by the postgresql-pangolin generator via dependencies.
      # Owned by postgres so postgresql-password-init (runs as postgres) can read it at runtime.
      files."password" = {
        secret = true;
        owner = "postgres";
        group = "postgres";
        mode = "0400";
      };

      runtimeInputs = [pkgs.openssl];

      script = ''
        set -euo pipefail
        secret="$(openssl rand -base64 32)"
        db_password="$(openssl rand -hex 32)"

        cat > "$out/pangolin.env" <<EOF
        SERVER_SECRET=$secret
        POSTGRES_CONNECTION_STRING=postgresql://pangolin:$db_password@127.0.0.1:5432/pangolin
        EOF

        printf '%s' "$db_password" > "$out/password"
      '';
    };

    # Ensure pangolin starts only after the DB user password has been initialised
    systemd.services.pangolin = lib.mkIf (config.services.pangolin.enable or false) {
      wants = ["postgresql-password-init.service"];
      after = ["postgresql-password-init.service"];
    };

    clan.core.vars.generators.cloudflare-dns = {
      share = true;

      files."cloudflare-dns.env" = {
        secret = true;
        mode = "0400";
      };

      prompts.token = {
        description = "Cloudflare API token for DNS-01 ACME challenge (Zone > DNS > Edit)";
        type = "hidden";
        persist = true;
      };

      runtimeInputs = [pkgs.coreutils];

      script = ''
        set -euo pipefail
        token="$(cat "$prompts/token")"

        cat > "$out/cloudflare-dns.env" <<EOF
        CF_DNS_API_TOKEN=$token
        EOF
      '';
    };
  };
}
