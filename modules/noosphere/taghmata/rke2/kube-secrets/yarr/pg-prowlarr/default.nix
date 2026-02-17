{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators."pg-prowlarr-sopssecret" = {
      share = true;

      prompts.pg-prowlarr-username = {
        description = "DB Username";
        type = "line";
        persist = false;
      };

      prompts.pg-prowlarr-password = {
        description = "DB Password";
        type = "hidden";
        persist = false;
      };

      files."pg-prowlarr-sopssecret".secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                username="$(tr -d '\r\n' < "$prompts/pg-prowlarr-username")"
                password="$(tr -d '\r\n' < "$prompts/pg-prowlarr-password")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/pg-prowlarr-sopssecret" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: pg-prowlarr-password
          namespace: yarr
        spec:
          secretTemplates:
            - name: pg-prowlarr-password
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
