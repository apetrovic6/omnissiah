# The M1 pilot (forge.ugalabugala.org/manjo/pilot) as a NixOS service: the same build the
# cluster's image is made from, run by the product's own nixosModules.api.
#
# The `pilot` flake input pins the revision; a rollout is `nix flake update pilot` plus a deploy.
#
# Peer auth over the socket: the service runs as a fixed `pilot` account, and Postgres maps
# the OS user to the role of the same name (`local all all peer` in rites/postgresql.nix).
# No password exists anywhere. The imperium user also enrols the database in the nightly
# pg_dump.
#
# The template namespaces the module by product: `services.pilot.api`, unit `pilot-api.service`,
# `/etc/pilot/api.toml`. The account is pinned to `pilot` below rather than the default
# `pilot-api`, because the Postgres role is named after it.
#
# Reachable at https://pilot.<lab-domain> via Caddy on the LAN/VPN only, like kaneo.
{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;

  # mkDomain is a Caddy placeholder, and the service needs the literal origin. The caddy-env
  # `domain` var ends in a newline, hence removeSuffix.
  domain = lib.removeSuffix "\n" config.clan.core.vars.generators."caddy-env".files."domain".value;
  cookieKey = config.clan.core.vars.generators.pilot-cookie-key.files."cookie-key";

  # 5000, the service's committed port, is already taken on this host.
  port = 5101;
  account = "pilot";
in {
  imports = [self.inputs.pilot.nixosModules.api];

  services.imperium.postgresql.users.${account} = {
    databases = [account];
    ensureDBOwnership = true;
    # Peer auth only, so nothing ever types it; it exists because every imperium user gets one.
    generatePassword = true;
  };

  services.pilot.api = {
    enable = true;
    inherit port;
    host = "127.0.0.1";

    dynamicUser = false;
    user = account;
    group = account;

    database.url = "postgres:///${account}?host=/run/postgresql";

    # The OIDC provider the service checks access tokens against; it refuses to start without
    # one. The same Pocket ID client (`pilot`) as the cluster deployment.
    environment.APP__AUTH__ISSUER = "https://id.noosphere.uk";

    # Web login through the service (template ADR 0029). The public origin is the redirect
    # target registered in Pocket ID (`auth.webHosts` in taghmata/_products.nix) and the CSRF
    # origin; the cookie key encrypts the session cookie. Rotating the key signs everyone out.
    environment.APP__AUTH__PUBLIC_URL = "https://pilot.${domain}";
    credentials.APP__AUTH__COOKIE_KEY = cookieKey.path;
  };

  # 32 random bytes, base64: what `auth.cookie_key` expects. Generated, never typed. Root-owned:
  # systemd reads it for LoadCredential (the module's `credentials`), the service reads the copy.
  clan.core.vars.generators.pilot-cookie-key = {
    files."cookie-key" = {
      secret = true;
      mode = "0400";
    };
    runtimeInputs = [pkgs.openssl];
    script = ''
      openssl rand -base64 32 > "$out/cookie-key"
    '';
  };

  services.caddy.virtualHosts."${mkDomain "pilot"}".extraConfig =
    mkRevProxyVHost {inherit port;};
}
