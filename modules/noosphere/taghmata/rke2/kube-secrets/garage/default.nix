{...}: let
  ageKey = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
  fileName = "garage-rpc-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileName} = {
      share = true;

      files.${fileName}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileName}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileName}
          namespace: argocd
        spec:
          secretTemplates:
            - name: ${fileName}
              type: Opaque
              stringData:
                rpc_secret: "$clientId"
        EOF
      '';
    };
  };
}
