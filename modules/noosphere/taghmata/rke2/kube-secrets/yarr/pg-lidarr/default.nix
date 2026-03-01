{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators."pg-lidarr-sopssecret" = {
      share = true;

      prompts.pg-lidarr-username = {
        description = "DB Username";
        type = "line";
        persist = false;
      };

      prompts.pg-lidarr-password = {
        description = "DB Password";
        type = "hidden";
        persist = false;
      };

      files."pg-lidarr-sopssecret".secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops];

      script = ''
                set -euo pipefail

                username="$(tr -d '\r\n' < "$prompts/pg-lidarr-username")"
                password="$(tr -d '\r\n' < "$prompts/pg-lidarr-password")"


        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/pg-lidarr-sopssecret" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: pg-lidarr-password
          namespace: yarr
        spec:
          secretTemplates:
            - name: pg-lidarr-password
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
