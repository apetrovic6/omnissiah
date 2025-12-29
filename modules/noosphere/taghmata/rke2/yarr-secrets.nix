{...} : {
  flake.nixosModules.noosphere = {pkgs,...}: {
    clan.core.vars.generators.yarr-secrets = {
      share = false;

      files.pg-seerr-username = {
        secret = false;
      };

      prompts.pg-seerr-username = {
        description = "DB Username";
        type = "hidden";
        persist = false;
      };

      prompts.pg-seerr-password= {
        description = "DB Password";
        type = "hidden";
        persist = false;
      };

      files.pg-seerr-sopssecret.secret = true;

      runtimeInputs = [pkgs.coreutils];
    
      script = ''
        set -euo pipefail

        username="$(tr -d '\r\n' < "$prompts/pg-seerr-username")"
        password="$(tr -d '\r\n' < "$prompts/pg-seerr-password")"

        printf "%s" "$username" > "$out/pg-seerr-username"
        
        cat > "$out/pg-seerr-sopssecret.yaml" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: pg-seerr-password
          namespace: yarr
        spec:
          secretTemplates:
            - name: pg-seerr-password
              metadata:
                name: pg-seerr-password
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
