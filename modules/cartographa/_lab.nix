# The lab's own domain, beside noosphere.uk (./_noosphere-values.nix):
# Forgejo, ntfy and the other services on cerberus behind Caddy, and the
# Matrix homeserver on cypramundi.
#
# On cerberus Caddy reads it at runtime as {$LAB_DOMAIN} (the caddy-env var),
# so Caddy's own config never contains it; modules that need the name at
# evaluation time take it from here.
rec {
  domain = "ugalabugala.org";
  matrix = {
    # The part after the colon in user IDs (`@me:ugalabugala.org`).
    serverName = domain;
    host = "matrix.${domain}";
    homeserver = "https://${matrix.host}";
  };
}
