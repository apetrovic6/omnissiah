# Confidential OIDC clients in Pocket ID, and the Kubernetes Secret that hands
# each one's id and secret to its app.
#
#   pharos.clients.karakeep = {
#     name = "karakeep";
#     url = "https://karakeep.noosphere.uk";
#     callbacks = ["/api/auth/callback/custom"];
#     secret.namespace = "karakeep";
#   };
#
# declares `pocketid_client.karakeep` and `kubernetes_secret_v1.karakeep-oidc`.
# The secret goes straight from the provider into the cluster, so no person
# ever copies it.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  withSecret = lib.filterAttrs (_: client: client.secret != null) config.pharos.clients;
in {
  options.pharos.clients = mkOption {
    default = {};
    description = "OIDC clients, by resource name.";
    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        name = mkOption {
          type = types.str;
          description = "Name shown in Pocket ID.";
        };
        url = mkOption {
          type = types.str;
          description = "Where the app lives: its launch URL and logout callback.";
        };
        callbacks = mkOption {
          type = types.listOf types.str;
          description = "Login callbacks: paths under `url`, or whole URLs.";
        };
        groups = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "`pocketid_group` resources allowed to log in; everyone when empty.";
        };
        secret = mkOption {
          default = null;
          description = "The Kubernetes Secret to write the credentials to, if any.";
          type = types.nullOr (types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                default = "${name}-oidc";
              };
              namespace = mkOption {type = types.str;};
              labels = mkOption {
                type = types.attrsOf types.str;
                default = {};
              };
              idKey = mkOption {
                type = types.str;
                default = "client-id";
              };
              secretKey = mkOption {
                type = types.str;
                default = "client-secret";
              };
            };
          });
        };
      };
    }));
  };

  config.resource = {
    pocketid_client = lib.mapAttrs (_: client:
      {
        inherit (client) name;
        callback_urls = map (callback:
          if lib.hasPrefix "/" callback
          then client.url + callback
          else callback)
        client.callbacks;
        logout_callback_urls = [client.url];
        pkce_enabled = false;
        launch_url = client.url;
      }
      // lib.optionalAttrs (client.groups != []) {
        allowed_user_groups = map (group: "\${pocketid_group.${group}.id}") client.groups;
      })
    config.pharos.clients;

    kubernetes_secret_v1 = lib.mapAttrs' (key: client:
      lib.nameValuePair client.secret.name {
        metadata =
          {inherit (client.secret) name namespace;}
          // lib.optionalAttrs (client.secret.labels != {}) {inherit (client.secret) labels;};
        data = {
          ${client.secret.idKey} = "\${pocketid_client.${key}.id}";
          ${client.secret.secretKey} = "\${pocketid_client.${key}.client_secret}";
        };
      })
    withSecret;
  };
}
