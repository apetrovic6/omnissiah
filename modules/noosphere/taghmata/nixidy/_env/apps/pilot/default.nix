# The M1 pilot: a rust-app-template product (forge.ugalabugala.org/manjo/pilot), run from its
# Harbor image. It is the canary for template bumps, and holds no real data.
#
# A rollout is a change to `tag` (the product's git revision, which its CI tags the image
# with), then a re-render from a clean worktree.
{config, ...}: let
  namespace = "pilot";
  domain = config.noosphere.domain;
  objectStoreName = "pilot-object-store";
in {
  imports = [
    ../../../_modules/templates/garage-object-store.nix
    ../../../_modules/templates/database-template.nix
    ../../../_modules/templates/rust-service.nix
  ];

  applications.pilot = {
    inherit namespace;
    createNamespace = true;

    templates.garageObjectStore.${objectStoreName} = {
      inherit namespace;
      destinationPath = "s3://pilot/backups";
      S3Credentials = {
        accessKeyId = {
          name = "pilot-s3-secret-key";
          key = "MINIO_ACCESS_KEY_ID";
        };
        secretAccessKey = {
          name = "pilot-s3-secret-key";
          key = "MINIO_SECRET_ACCESS_KEY";
        };
      };
    };

    # pg-pilot, bootstrapped by CNPG with database `app` owned by `app`; its `pg-pilot-app`
    # secret carries the URL the service reads.
    templates.cnpg-database-cluster.pilot = {
      inherit namespace;
      overrideObjectStore = objectStoreName;
      cluster.spec = {
        # A canary with no real data: one instance, small buffers.
        instances = 1;
        postgresql.parameters = {
          shared_buffers = "128MB";
          max_connections = "50";
          log_statement = "ddl";
        };
        plugins = [
          {
            isWALArchiver = true;
            parameters.barmanObjectName = objectStoreName;
          }
        ];
      };
      databases = [];
      backups = {
        scheduledBackups = [
          {
            metadata.namespace = namespace;
            spec = {
              schedule = "0 30 2 * * *";
              backupOwnerReference = "self";
              immediate = true;
            };
          }
        ];
        onDemandBackups = [];
      };
    };

    templates.rust-service.pilot = {
      inherit namespace;
      image = "harbor.${domain}/pilot/api";
      tag = "0f767c0c30ff2d12841cb67119dec0298b7ca7e4";
      database.cluster = "pg-pilot";
      host = "pilot.${domain}";
      # The OIDC provider the service checks access tokens against (crates/oidc, ADR 0027);
      # the service refuses to start without it. Pocket ID's client for this product is `pilot`,
      # which is also the audience the committed config names.
      env.APP__AUTH__ISSUER = "https://id.${domain}";
      glance = {
        name = "Pilot";
        icon = "di:rust";
        description = "rust-app-template pilot";
        category = "dev";
      };
    };
  };
}
