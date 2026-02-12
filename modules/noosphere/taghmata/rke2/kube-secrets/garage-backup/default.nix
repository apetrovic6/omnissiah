{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  fileNameRpc = "garage-backup-rpc-secret";
  fileNameAdmin = "garage-backup-admin-token";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileNameRpc} = {
      share = true;

      files.${fileNameRpc}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileNameRpc}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileNameRpc}
          namespace: garage-operator
        spec:
          secretTemplates:
            - name: ${fileNameRpc}
              type: Opaque
              stringData:
                rpc-secret: "$secret"
        EOF
      '';
    };

    clan.core.vars.generators.${fileNameAdmin} = {
      share = true;

      files.${fileNameAdmin}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileNameAdmin}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileNameAdmin}
          namespace: garage-operator
        spec:
          secretTemplates:
            - name: ${fileNameAdmin}
              type: Opaque
              stringData:
                admin-token: "$secret"
        EOF
      '';
    };
  };
}
