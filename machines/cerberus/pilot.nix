# The M1 pilot (forge.ugalabugala.org/manjo/pilot) as a NixOS service: the same build the
# cluster's image is made from, run by the product's own nixosModules.api.
#
# NOT imported yet. To enable, once the pilot repo has its first master commit:
#   1. flake.nix inputs:
#        pilot = {
#          url = "git+https://forge.ugalabugala.org/manjo/pilot";
#          inputs.nixpkgs.follows = "nixpkgs";
#        };
#      then `nix flake update pilot`.
#   2. add ./pilot.nix to the imports in ./configuration.nix and deploy.
#
# Peer auth over the socket: the service runs as a fixed `pilot` account, and Postgres maps
# the OS user to the role of the same name (`local all all peer` in rites/postgresql.nix).
# No password exists anywhere. The imperium user also enrols the database in the nightly
# pg_dump.
#
# The product module's option namespace is the service's crate name (`services.api`), so a
# second product with an `api` service cannot share this host until the template namespaces
# it; see the M1 notes.
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
  };

  services.api = {
    enable = true;
    inherit port;
    host = "127.0.0.1";

    dynamicUser = false;
    user = account;
    group = account;

    database.url = "postgres:///${account}?host=/run/postgresql";
  };

  services.caddy.virtualHosts."${mkDomain "pilot"}".extraConfig =
    mkRevProxyVHost {inherit port;};
}
