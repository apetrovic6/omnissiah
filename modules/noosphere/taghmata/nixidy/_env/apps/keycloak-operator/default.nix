{
  pkgs,
  config,
  ...
}: let
  keycloakVersion = "26.5.0";
  keycloakCrds1 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${keycloakVersion}/kubernetes/keycloaks.k8s.keycloak.org-v1.yml";
    hash = "sha256-hWZ5SkIaI7ZDrHoFPgDpE8InoFGe3EPwEJfzeYO7kV8=";
  };

  keycloakCrds2 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${keycloakVersion}/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml";
    hash = "sha256-MlKbZ7Mst/cKVKDoaL8Jb3Ul13tmcHIiK0bSWLlLaDY=";
  };

  keycloakOperator = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${keycloakVersion}/kubernetes/kubernetes.yml";
    hash = "sha256-ROYGpL+GpFo042JuPE1gY7eZO8blhucyYJDBfY248kg=";
  };

  namespace = "keycloak";
  db-cluster-name = "pg-keycloak";
  objectStoreName = "keycloak-object-store";
  domain = config.noosphere.domain;
in {
  imports = [
    ../../../_modules/templates/garage-object-store.nix
    ../../../_modules/templates/database-template.nix
  ];

  applications.keycloak = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile keycloakCrds1)
      (builtins.readFile keycloakCrds2)
      (builtins.readFile keycloakOperator)

      ''
        apiVersion: k8s.keycloak.org/v2alpha1
        kind: Keycloak
        metadata:
          name: ${namespace}
        spec:
          instances: 3
          db:
            vendor: postgres
            host: pg-keycloak-rw
            database: app
            port: 5432
            usernameSecret:
              name: ${db-cluster-name}-app
              key: username
            passwordSecret:
              name: ${db-cluster-name}-app
              key: password
          http:
            httpEnabled: true
          ingress:
            annotations:
              glance/name: Keycloak
              glance/icon:  di:keycloak
              glance/url:  https://keycloak.${domain}
              glance/description: "Identity Provider"
              glance/id: keycloak
              glance/parent: keycloak
              category: security
            enabled: true
            tlsSecret: keycloak-tls
            className: traefik
          hostname:
            hostname: keycloak.${domain}
          proxy:
            headers: xforwarded # double check your reverse proxy sets and overwrites the X-Forwarded-* headers
      ''

      ''
        apiVersion: k8s.keycloak.org/v2alpha1
        kind: KeycloakRealmImport
        metadata:
          name: adeptus-terra
        spec:
          keycloakCRName: adeptus-terra
          realm:
            id: adeptus-terra
            realm: adeptus-terra
            displayName: AdeptusTerra
            enabled: true
      ''

      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: keycloak-tls
          namespace: ${namespace}
        spec:
          secretName: keycloak-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - keycloak.${domain}
      ''
    ];

    templates.garageObjectStore."${objectStoreName}" = {
      inherit namespace;
      # Migrated off the failing NFS-backed `garage` cluster onto the
      # operator-managed `garage-backup` cluster (its keycloak bucket/key are
      # provisioned and the creds are reflected as keycloak-s3-secret-key).
      awsDefaultRegion = "backup";
      destinationPath = "s3://keycloak/backups";
      endpointUrl = "http://garage-backup.garage-operator.svc.cluster.local:3900";
      S3Credentials = {
        accessKeyId = {
          name = "keycloak-s3-secret-key";
          key = "MINIO_ACCESS_KEY_ID";
        };
        secretAccessKey = {
          name = "keycloak-s3-secret-key";
          key = "MINIO_SECRET_ACCESS_KEY";
        };
      };
    };

    templates.cnpg-database-cluster.keycloak = {
      inherit namespace;

      cluster = {
        spec.plugins = [
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
              schedule = "0 2 0 * * *"; # Backup at 2AM every night
              backupOwnerReference = "self";
              immediate = true;
            };
          }
        ];

        onDemandBackups = [{spec = {};}];
      };
    };
  };
}
