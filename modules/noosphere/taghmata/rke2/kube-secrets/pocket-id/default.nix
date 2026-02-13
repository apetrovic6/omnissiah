{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  pocketIdEncryptionKey = "pocket-id-encryption-key";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${pocketIdEncryptionKey} = {
      share = true;

      files.${pocketIdEncryptionKey}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -base64 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${pocketIdEncryptionKey}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${pocketIdEncryptionKey}
          namespace: pocket-id
        spec:
          secretTemplates:
            - name: ${pocketIdEncryptionKey}
              type: Opaque
              stringData:
                encryption-key: "$secret"
        EOF
      '';
    };
  };
}
