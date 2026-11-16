# Ingress helpers for the applications.
#
# `ingresses.<name>`, an option of every application, for the common case: one
# host, one path, served by Traefik with a certificate from cert-manager.
#
#   applications.excalidraw.ingresses.excalidraw-ip-root = {
#     inherit namespace;
#     host = "excalidraw.${domain}";
#     service = "excalidraw";
#     port = 80;
#     tlsSecret = "excalidraw-tls";
#     glance = {
#       name = "Excalidraw";
#       icon = "di:excalidraw";
#       description = "Draw diagrams";
#       category = "utils";
#     };
#   };
#
# It becomes `resources.ingresses.<name>`. Anything it cannot express (several
# hosts or paths) is still written as `resources.ingresses` directly.
#
# `ingressAnnotations`, a module argument, builds the same annotations for a
# chart that renders its own Ingress and only takes annotations as a value.
{lib}: let
  inherit (lib) mkOption types optionalAttrs mapAttrs' nameValuePair filterAttrs;

  issuerName = "letsencrypt-cloudflare";

  # The Glance dashboard discovers services from these annotations
  # (apps/glances): `category` is the group, `id` and `parent` build the tree.
  glanceAnnotations = glance:
    mapAttrs' (key: value:
      nameValuePair (
        if key == "category"
        then "category"
        else "glance/${key}"
      )
      value)
    (filterAttrs (_: value: value != null) glance);

  ingressAnnotations = {
    # Request a certificate from cert-manager.
    issuer ? true,
    # Traefik entrypoints the router listens on; null leaves it to Traefik.
    entrypoints ? null,
    # Keep ArgoCD from pruning or deleting the Ingress.
    protect ? false,
    # name, icon, description, category, and optionally url, id, parent.
    glance ? null,
    extra ? {},
  }:
    optionalAttrs issuer {"cert-manager.io/cluster-issuer" = issuerName;}
    // optionalAttrs (entrypoints != null) {"traefik.ingress.kubernetes.io/router.entrypoints" = entrypoints;}
    // optionalAttrs protect {"argocd.argoproj.io/sync-options" = "Prune=false,Delete=false";}
    // optionalAttrs (glance != null) (glanceAnnotations glance)
    // extra;

  glanceType = types.nullOr (types.submodule {
    options = {
      name = mkOption {type = types.str;};
      icon = mkOption {type = types.str;};
      description = mkOption {type = types.str;};
      category = mkOption {type = types.str;};
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      id = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      parent = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  });

  ingressType = types.submodule {
    options = {
      namespace = mkOption {type = types.str;};
      host = mkOption {
        type = types.str;
        description = "Host name the Ingress answers for and the certificate is issued to.";
      };
      path = mkOption {
        type = types.str;
        default = "/";
      };
      service = mkOption {
        type = types.str;
        description = "Service that receives the traffic.";
      };
      port = mkOption {
        type = types.either types.port types.str;
        description = "Port of the Service, by number or by name.";
      };
      tlsSecret = mkOption {
        type = types.str;
        description = "Secret cert-manager stores the certificate in.";
      };
      issuer = mkOption {
        type = types.bool;
        default = true;
      };
      entrypoints = mkOption {
        type = types.nullOr types.str;
        default = "websecure";
      };
      protect = mkOption {
        type = types.bool;
        default = false;
      };
      glance = mkOption {
        type = glanceType;
        default = null;
      };
      annotations = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Further annotations.";
      };
    };
  };

  module = {config, ...}: {
    options.ingresses = mkOption {
      type = types.attrsOf ingressType;
      default = {};
      description = "Single-host Traefik ingresses of this application.";
    };

    config.resources.ingresses =
      lib.mapAttrs (_: ingress: {
        metadata = {
          inherit (ingress) namespace;
          annotations = ingressAnnotations {
            inherit (ingress) issuer entrypoints protect;
            glance =
              if ingress.glance == null
              then null
              else
                ingress.glance
                // {
                  url =
                    if ingress.glance.url != null
                    then ingress.glance.url
                    else "https://${ingress.host}";
                };
            extra = ingress.annotations;
          };
        };

        spec = {
          ingressClassName = "traefik";

          tls = [
            {
              secretName = ingress.tlsSecret;
              hosts = [ingress.host];
            }
          ];

          rules = [
            {
              inherit (ingress) host;
              http.paths = [
                {
                  inherit (ingress) path;
                  pathType = "Prefix";
                  backend.service = {
                    name = ingress.service;
                    port =
                      if builtins.isInt ingress.port
                      then {number = ingress.port;}
                      else {name = ingress.port;};
                  };
                }
              ];
            }
          ];
        };
      })
      config.ingresses;
  };
in {
  inherit module ingressAnnotations;
}
