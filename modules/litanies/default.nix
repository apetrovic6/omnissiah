{lib, ...}: {
  flake.lib = {
    mkDomain = subdomain: "${subdomain}.{$LAB_DOMAIN}";

    # `resolvers` is not optional here. After writing the _acme-challenge TXT
    # to Cloudflare, certmagic looks up the zone's authoritative nameservers
    # through the *host* resolver and polls those for the record. On cerberus
    # that lookup hits its own Technitium, which holds ugalabugala.org as a
    # primary zone (`dig NS ugalabugala.org` -> `cerberus.`, not the two
    # clint/simone.ns.cloudflare.com), so it polls a server the record will
    # never appear on and every issuance dies with "timed out waiting for
    # record to fully propagate". It looked intermittent rather than broken
    # only because systemd-resolved sometimes picked an upstream instead.
    # Pinning public resolvers keeps the propagation check off split-horizon
    # DNS entirely.
    mkRevProxyVHost = {
      port,
      host ? "localhost",
    }: ''
      reverse_proxy "http://${host}:${toString port}"
      tls {
            dns cloudflare {$CLOUDFLARE_API_TOKEN}
            resolvers 1.1.1.1 1.0.0.1
      }
    '';
  };
}
