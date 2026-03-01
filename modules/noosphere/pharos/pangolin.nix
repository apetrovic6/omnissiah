{config, ...}: let
in {
  flake.nixosModules.pharos = {pkgs, ...}: let
    geolite2-country-db = pkgs.runCommand "geolite2-country-db" {} ''
      mkdir -p $out
      tar xzf ${pkgs.fetchurl {
        url = "https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/GeoLite2-Country.tar.gz";
        hash = "sha256-61uX4tElLST7YMgtwyDp1e3y1DTpP8mUKmN5VlTh25Q=";
      }} --strip-components=1
      cp GeoLite2-Country.mmdb $out/
    '';
  in {
    services.pangolin.settings.server.maxmind_db_path = "${geolite2-country-db}/GeoLite2-Country.mmdb";

    clan.core.vars.generators.pangolin = {
      files."pangolin.env" = {
        secret = true;
        mode = "0400";
      };

      runtimeInputs = [pkgs.openssl];

      script = ''
        set -euo pipefail
        secret="$(openssl rand -base64 32)"


        cat  > "$out/pangolin.env" <<EOF
        SERVER_SECRET=$secret
        EOF
      '';
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
