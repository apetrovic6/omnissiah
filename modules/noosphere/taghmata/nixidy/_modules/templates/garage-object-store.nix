{lib, ...}: let
  inherit (lib) mkOption types;
in {
  templates.garageObjectStore = {
    options = {
      name = mkOption {
        type = types.str;
        default = "";
        description = "Name of the object store";
      };

      namespace = mkOption {
        type = types.str;
        default = "";
        description = "Namespace for the object store";
      };

      AwsDefaultRegion = mkOption {
        type = types.str;
        default = "garage";
        description = "Region of the Garage object store";
      };

      destinationPath = mkOption {
        type = types.str;
        default = "s3://cnpg-backup-bucket/backups";
        description = "Path in the bucket";
      };

      endpointUrl = mkOption {
        type = types.str;
        default = "http://garage.garage.svc.cluster.local:3900";
        description = "Garage Endpoint";
      };

      S3Credentials = {
        accessKeyId = {
          name = mkOption {
            type = types.str;
            default = "barman-s3-secret-key";
            description = "Name of the secret";
          };

          key = mkOption {
            type = types.str;
            default = "ACCESS_KEY_ID";
            description = "Key of the secret";
          };
        };

        secretAccessKey = {
          name = mkOption {
            type = types.str;
            default = "barman-s3-secret-key";
            description = "Name of the secret";
          };

          key = mkOption {
            type = types.str;
            default = "ACCESS_SECRET_KEY";
            description = "Key of the secret";
          };
        };
      };

      wal.compression = mkOption {
        type = types.str;
        default = "gzip";
        description = "Compression type.";
      };
    };
  };

  output = {config, ...}: let
    cfg = config;
  in {
    resources.objectStores.${cfg.name} = {
      metadata.namespace = cfg.namespace;
      spec = {
        instanceSidecarConfiguration = {
          env = [
            # MUST match Garage's s3_region in garage.toml / chart values
            {
              name = "AWS_DEFAULT_REGION";
              value = cfg.AwsDefaultRegion;
            }

            # Recommended for some S3-compatible implementations (boto3 checksum behavior)
            {
              name = "AWS_REQUEST_CHECKSUM_CALCULATION";
              value = "when_required";
            }
            {
              name = "AWS_RESPONSE_CHECKSUM_VALIDATION";
              value = "when_required";
            }

            # Optional: makes boto3 stop trying IMDS in some environments
            # { name = "AWS_EC2_METADATA_DISABLED"; value = "true"; }
          ];
        };
        configuration = {
          destinationPath = cfg.destinationPath;
          endpointURL = cfg.endpointUrl;
          s3Credentials = let
            s3 = cfg.S3Credentials;
          in {
            accessKeyId = {
              name = s3.accessKeyId.name;
              key = s3.accessKeyId.key;
            };

            secretAccessKey = {
              name = s3.secretAccessKey.name;
              key = s3.secretAccessKey.key;
            };
          };
          wal.compression = cfg.wal.compression;
        };
      };
    };
  };
}
