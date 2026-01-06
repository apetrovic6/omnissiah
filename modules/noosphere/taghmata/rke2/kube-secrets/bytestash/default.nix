{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  bytestashJwtSecret = "bytestash-jwt-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${bytestashJwtSecret} = {
      share = true;

      files.${bytestashJwtSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${bytestashJwtSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${bytestashJwtSecret}
          namespace: bytestash
        spec:
          secretTemplates:
            - name: ${bytestashJwtSecret}
              type: Opaque
              stringData:
                jwt-key: "$secret"
                expiry: "24h"
        EOF
      '';
    };
  };
}
