# The Hermes Agent dashboard. Hermes itself runs on ryza, outside the cluster
# (modules/rites/hermes.nix); this is only the way in: Traefik, a certificate,
# and an ExternalName Service to ryza (`outside`, _modules/ingress.nix).
#
# Login happens in Hermes itself (OIDC against Pocket ID, admins only); ryza
# accepts the port only from the cluster nodes.
{...}: {
  nixidy.envs.prod.apps.hermes = {config, ...}: let
    namespace = "hermes";
    domain = config.noosphere.domain;
  in {
    applications.hermes = {
      inherit namespace;
      createNamespace = true;

      ingresses.hermes = {
        inherit namespace;
        outside = "ryza";
        service = "hermes";
        port = 9119;
        host = "hermes.${domain}";
        tlsSecret = "hermes-tls";
        glance = {
          name = "Hermes";
          icon = "di:openai";
          description = "Always-on agent on ryza";
          category = "utils";
        };
      };
    };
  };
}
