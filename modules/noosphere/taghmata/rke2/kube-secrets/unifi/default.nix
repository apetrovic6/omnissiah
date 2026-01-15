{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  unifiMongoPassword = "unifi-mongodb-password";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
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
          namespace: unifi
        spec:
          secretTemplates:
            - name: ${unifiMongoPassword}
              type: Opaque
              stringData:
                password: "$password"
        EOF
      '';
    };
  };
}
