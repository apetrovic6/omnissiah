{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  barmanS3Storage = "barman-s3-secret-key";
  namespacesToReplicate = "yarr,harbor,keycloak,woodpecker,forgejo,vikunja";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${barmanS3Storage} = {
      share = true;

      prompts.access-key-id = {
        description = "Enter Access Key ID: ";
        type = "line";
        persist = false;
      };

      prompts.access-key-secret = {
        description = "Enter Access Key Secret: ";
        type = "hidden";
        persist = false;
      };

      files.${barmanS3Storage}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                access_key="$(tr -d '\r\n' < "$prompts/access-key-id")"
                secret_key="$(tr -d '\r\n' < "$prompts/access-key-secret")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${barmanS3Storage}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${barmanS3Storage}
          namespace: reflector
        spec:
          secretTemplates:
            - name: ${barmanS3Storage}
              labels:
                cnpg.io/reload: "true"
              annotations:
                reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
                reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "${namespacesToReplicate}"
                reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
                reflector.v1.k8s.emberstack.com/reflection-auto-namespaces: "${namespacesToReplicate}"
              type: Opaque
              stringData:
                ACCESS_KEY_ID: "$access_key"
                ACCESS_SECRET_KEY: "$secret_key"
        EOF
      '';
    };
  };
}
