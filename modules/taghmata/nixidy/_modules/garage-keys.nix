# `garage.keys.<name>`: an S3 access key on one of the Garage clusters and the
# buckets it may use, declared by whichever application needs them.
#
#   garage.keys.vikunja = {
#     cluster = "backup";
#     secret.namespace = "vikunja";
#   };
#
# creates the bucket `vikunja` and the key `vikunja` on garage-backup, and has
# the operator write the credentials to the Secret `vikunja-s3-secret-key`,
# which reflector copies into the vikunja namespace.
#
# Wherever it is declared, the GarageKey and GarageBucket are rendered into the
# garage-operator application, next to the clusters. That is also where they
# have always been: with auto-sync and prune on, an object that changed
# application would be deleted from one and created in the other, and deleting
# a GarageBucket deletes the bucket.
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types optionalAttrs mapAttrs concatMap nameValuePair attrValues;

  namespace = "garage-operator";

  keyType = types.submodule ({name, ...}: {
    options = {
      cluster = mkOption {
        type = types.enum ["main" "backup"];
        description = "The Garage cluster: garage-main (application data) or garage-backup (database backups).";
      };

      buckets = mkOption {
        type = types.listOf types.str;
        default = [name];
        description = "Buckets to create and give this key access to.";
      };

      bucketSpec = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = "Further GarageBucket spec per bucket, such as quotas or lifecycle rules.";
      };

      permissions = mkOption {
        type = types.submodule {
          options = {
            read = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this key can read objects in its buckets.";
            };
            write = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this key can write objects in its buckets.";
            };
          };
        };
        default = {};
        description = ''
          Object access granted to this key on each of its listed buckets.
          This does not change owner (default: true). Set owner = false
          as well for a read-only key that must not administer the bucket.
        '';
      };

      owner = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the key owns its buckets. Ownership is what authorises
          bucket-level calls such as PutBucketCors; reading and writing objects
          does not need it.
        '';
      };

      importSecret = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Import the key pair from this Secret in the garage-operator namespace
          (keys access-key-id and secret-access-key) and do not generate one.
          For consumers outside the cluster, whose credentials come from a clan
          var.
        '';
      };

      secret = mkOption {
        default = null;
        description = "Have the operator write the credentials to a Secret, reflected into the consumer's namespace.";
        type = types.nullOr (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              default = "${name}-s3-secret-key";
            };
            namespace = mkOption {
              type = types.str;
              description = "Namespace reflector copies the Secret into.";
            };
            accessKeyIdKey = mkOption {
              type = types.nullOr types.str;
              default = "MINIO_ACCESS_KEY_ID";
              description = "Key of the access key id in the Secret; null for the operator's default (access-key-id).";
            };
            secretAccessKeyKey = mkOption {
              type = types.nullOr types.str;
              default = "MINIO_SECRET_ACCESS_KEY";
              description = "Key of the secret access key in the Secret; null for the operator's default (secret-access-key).";
            };
          };
        });
      };
    };
  });

  clusterRef = key: {name = "garage-${key.cluster}";};

  bucketDefinitions = lib.groupBy (entry: entry.name) (concatMap (key:
    map (bucket:
      nameValuePair bucket {
        metadata = {inherit namespace;};
        spec = {clusterRef = clusterRef key;} // (key.bucketSpec.${bucket} or {});
      })
    key.buckets) (attrValues config.garage.keys));

  duplicateBuckets = builtins.attrNames (lib.filterAttrs (_: defs: builtins.length defs > 1) bucketDefinitions);
in {
  options.garage.keys = mkOption {
    type = types.attrsOf keyType;
    default = {};
    description = "Garage access keys and their buckets.";
  };

  config.applications.garage-operator.resources = {
    garageKeys =
      mapAttrs (_: key: {
        metadata = {inherit namespace;};
        spec =
          {
            clusterRef = clusterRef key;
            bucketPermissions =
              map (bucket: {
                bucketRef.name = bucket;
                inherit (key.permissions) read write;
                inherit (key) owner;
              })
              key.buckets;
          }
          // optionalAttrs (key.importSecret != null) {
            importKey.secretRef = {
              name = key.importSecret;
              inherit namespace;
            };
          }
          // optionalAttrs (key.secret != null) {
            secretTemplate =
              {
                inherit (key.secret) name;
                annotations = {
                  "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
                  "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = key.secret.namespace;
                  "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
                  "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = key.secret.namespace;
                };
              }
              // optionalAttrs (key.secret.accessKeyIdKey != null) {inherit (key.secret) accessKeyIdKey;}
              // optionalAttrs (key.secret.secretAccessKeyKey != null) {inherit (key.secret) secretAccessKeyKey;};
          };
      })
      config.garage.keys;

    garageBuckets = assert lib.assertMsg (duplicateBuckets == [])
    "garage.keys: each GarageBucket must be defined by only one key; duplicate buckets: ${lib.concatStringsSep ", " duplicateBuckets}";
      mapAttrs (_: defs: (builtins.head defs).value) bucketDefinitions;
  };
}
