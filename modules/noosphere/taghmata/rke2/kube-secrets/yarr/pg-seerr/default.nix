{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators."pg-seerr-sopssecret" = {
      share = true;

      prompts.pg-seerr-username = {
        description = "DB Username";
        type = "line";
        persist = false;
      };

      prompts.pg-seerr-password = {
        description = "DB Password";
        type = "hidden";
        persist = false;
      };

      files."pg-seerr-sopssecret".secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                username="$(tr -d '\r\n' < "$prompts/pg-seerr-username")"
                password="$(tr -d '\r\n' < "$prompts/pg-seerr-password")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/pg-seerr-sopssecret" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: pg-seerr-password
          namespace: yarr
        spec:
          secretTemplates:
            - name: pg-seerr-password
              labels:
                cnpg.io/reload: "true"
              type: Opaque
              stringData:
                username: "$username"
                password: "$password"
        EOF
      '';
    };
  };
}
