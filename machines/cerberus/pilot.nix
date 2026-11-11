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
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;

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
  };

  services.caddy.virtualHosts."${mkDomain "pilot"}".extraConfig =
    mkRevProxyVHost {inherit port;};
}
