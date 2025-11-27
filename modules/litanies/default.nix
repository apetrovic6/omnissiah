{...}: {
  flake.lib = {
    mkDomain = subdomain: "${subdomain}.{$LAB_DOMAIN}";

    mkRevProxyVHost = port: ''
      reverse_proxy "http://{$LAB_IP}:${toString port}"
      tls {
            dns cloudflare {$CLOUDFLARE_API_TOKEN}
      }
    '';
  };
}
