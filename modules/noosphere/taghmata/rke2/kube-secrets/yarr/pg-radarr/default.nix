{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators."pg-radarr-sopssecret" = {
      share = true;

      prompts.pg-radarr-username = {
        description = "DB Username";
        type = "line";
        persist = false;
      };

      prompts.pg-radarr-password = {
        description = "DB Password";
        type = "hidden";
        persist = false;
      };

      files."pg-radarr-sopssecret".secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                username="$(tr -d '\r\n' < "$prompts/pg-radarr-username")"
                password="$(tr -d '\r\n' < "$prompts/pg-radarr-password")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/pg-radarr-sopssecret" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: pg-radarr-password
          namespace: yarr
        spec:
          secretTemplates:
            - name: pg-radarr-password
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
