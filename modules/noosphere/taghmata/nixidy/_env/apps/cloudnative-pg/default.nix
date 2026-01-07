{
  charts,
  pkgs,
  ...
}: let
  barmanVersion = "0.10.0";
  barmanManifest = pkgs.fetchurl {
    url = "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${barmanVersion}/manifest.yaml";
    hash = "sha256-9yjeqQqt490v60xLOTX6dLyHQwdjU8lwY1kbHQrUuKQ=";
  };
in {
  applications.barman-cloud = {
    namespace = "cnpg-system";
    resources.objectStores.garage-store = {
      metadata.namespace = "yarr";
      spec = {
        instanceSidecarConfiguration = {
          env = [
            # MUST match Garage's s3_region in garage.toml / chart values
            {
              name = "AWS_DEFAULT_REGION";
              value = "garage";
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
          destinationPath = "s3://cnpg-backup-bucket/backups";
          endpointURL = "http://garage.garage.svc.cluster.local:3900";
          s3Credentials = {
            accessKeyId = {
              name = "barman-s3-secret-key";
              key = "ACCESS_KEY_ID";
            };

            secretAccessKey = {
              name = "barman-s3-secret-key";
              key = "ACCESS_SECRET_KEY";
            };
          };
          wal.compression = "gzip";
        };
      };
    };

    yamls = [
      (builtins.readFile barmanManifest)

      # ''
      #   apiVersion: barmancloud.cnpg.io/v1
      #   kind: ObjectStore
      #   metadata:
      #     name: minio-store
      #   spec:
      #     configuration:
      #       destinationPath: s3://backups/
      #       endpointURL: http://minio:9000
      #       s3Credentials:
      #         accessKeyId:
      #           name: minio
      #           key: ACCESS_KEY_ID
      #         secretAccessKey:
      #           name: minio
      #           key: ACCESS_SECRET_KEY
      #       wal:
      #         compression: gzip
      # ''
    ];
  };

  applications.cloudnativepg = let
    namespace = "cnpg-system";
  in {
    inherit namespace;
    createNamespace = true;

    helm.releases.cloudnative-pg = {
      chart = charts.cloudnative-pg.cloudnative-pg;
    };
  };
}
