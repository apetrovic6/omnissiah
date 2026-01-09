{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  crowAgentSecret = "crow-agent-secret";

in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${crowAgentSecret} = {
      share = true;

      files.${crowAgentSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 16)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${crowAgentSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${crowAgentSecret}
          namespace: crow
        spec:
          secretTemplates:
            - name: ${crowAgentSecret}
              type: Opaque
              stringData:
                CROW_AGENT_SECRET: "$secret"
        EOF
      '';
    };


  };
}
