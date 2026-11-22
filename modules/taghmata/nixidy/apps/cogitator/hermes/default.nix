# The Hermes Agent dashboard. Hermes itself runs on ryza, outside the cluster
# (modules/rites/hermes.nix); this is only the way in: Traefik, a certificate,
# and a Service whose single endpoint is ryza.
#
# A Service without a selector plus a hand-written EndpointSlice is the
# standard way to give an outside host a cluster Service: Traefik routes to it
# like to any pod. The slice is tied to the Service by the
# kubernetes.io/service-name label, and its port name must match the
# Service's.
#
# Login happens in Hermes itself (OIDC against Pocket ID, admins only); ryza
# accepts the port only from the cluster nodes.
{...}: {
  nixidy.envs.prod.apps.hermes = {
    config,
    cartographa,
    ...
  }: let
    namespace = "hermes";
    domain = config.noosphere.domain;
    port = 9119;
  in {
    applications.hermes = {
      inherit namespace;
      createNamespace = true;

      resources.services.hermes = {
        metadata = {inherit namespace;};
        spec.ports = [
          {
            name = "http";
            inherit port;
            targetPort = port;
            protocol = "TCP";
          }
        ];
      };

      resources.endpointSlices.hermes-ryza = {
        metadata = {
          inherit namespace;
          labels."kubernetes.io/service-name" = "hermes";
        };
        addressType = "IPv4";
        endpoints = [{addresses = [cartographa.hosts.ryza];}];
        ports = [
          {
            name = "http";
            inherit port;
            protocol = "TCP";
          }
        ];
      };

      ingresses.hermes = {
        inherit namespace port;
        host = "hermes.${domain}";
        service = "hermes";
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
