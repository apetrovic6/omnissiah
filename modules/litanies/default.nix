{lib, ...}: {
  flake.lib = {
    mkDomain = subdomain: "${subdomain}.{$LAB_DOMAIN}";

    mkRevProxyVHost = {
      port,
      host ? "localhost",
    }: ''
      reverse_proxy "http://${host}:${toString port}"
      tls {
            dns cloudflare {$CLOUDFLARE_API_TOKEN}
      }
    '';
  };
}
