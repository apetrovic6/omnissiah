{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators."pg-sonarr-sopssecret" = {
      share = true;

      prompts.pg-sonarr-username = {
        description = "DB Username";
        type = "line";
        persist = false;
      };

      prompts.pg-sonarr-password = {
        description = "DB Password";
        type = "hidden";
        persist = false;
      };

      files."pg-sonarr-sopssecret".secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                username="$(tr -d '\r\n' < "$prompts/pg-sonarr-username")"
                password="$(tr -d '\r\n' < "$prompts/pg-sonarr-password")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/pg-sonarr-sopssecret" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: pg-sonarr-password
          namespace: yarr
        spec:
          secretTemplates:
            - name: pg-sonarr-password
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
