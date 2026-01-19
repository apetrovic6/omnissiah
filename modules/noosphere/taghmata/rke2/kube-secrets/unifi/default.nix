{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  unifiMongoPassword = "unifi-mongodb-password";
  unifiS3SecretKey = "unifi-s3-secret-key";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    # MongoDB password secret
    clan.core.vars.generators.${unifiMongoPassword} = {
      share = true;

      files.${unifiMongoPassword}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
        set -euo pipefail

        # Generate a secure random password
        password="$(openssl rand -base64 32 | tr -d '\n')"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${unifiMongoPassword}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${unifiMongoPassword}
          namespace: unifi-controller
        spec:
          secretTemplates:
            - name: ${unifiMongoPassword}
              type: Opaque
              stringData:
                password: "$password"
                unifi: "$password"
                MONGODB_BACKUP_USER: backup
                MONGODB_BACKUP_PASSWORD: "$password"
                MONGODB_DATABASE_ADMIN_USER: databaseAdmin
                MONGODB_DATABASE_ADMIN_PASSWORD: "$password"
                MONGODB_CLUSTER_ADMIN_USER: clusterAdmin
                MONGODB_CLUSTER_ADMIN_PASSWORD: "$password"
                MONGODB_CLUSTER_MONITOR_USER: clusterMonitor
                MONGODB_CLUSTER_MONITOR_PASSWORD: "$password"
                MONGODB_USER_ADMIN_USER: userAdmin
                MONGODB_USER_ADMIN_PASSWORD: "$password"
        EOF
      '';
    };

    # S3 credentials for backups
    clan.core.vars.generators.${unifiS3SecretKey} = {
      share = true;

      prompts.access-key = {
        description = "Garage S3 Access Key for UniFi MongoDB backups";
        type = "line";
        persist = false;
      };

      prompts.secret-key = {
        description = "Garage S3 Secret Key for UniFi MongoDB backups";
        type = "hidden";
        persist = false;
      };

      files.${unifiS3SecretKey}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
        set -euo pipefail

        access_key="$(tr -d '\r\n' < "$prompts/access-key")"
        secret_key="$(tr -d '\r\n' < "$prompts/secret-key")"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${unifiS3SecretKey}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${unifiS3SecretKey}
          namespace: unifi-controller
        spec:
          secretTemplates:
            - name: ${unifiS3SecretKey}
              type: Opaque
              stringData:
                AWS_ACCESS_KEY_ID: "$access_key"
                AWS_SECRET_ACCESS_KEY: "$secret_key"
        EOF
      '';
    };
  };
}
