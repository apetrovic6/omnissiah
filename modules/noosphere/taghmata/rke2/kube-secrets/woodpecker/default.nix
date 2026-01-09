{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  woodpeckerAgentSecret = "woodpecker-agent-secret";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${woodpeckerAgentSecret} = {
      share = true;

      files.${woodpeckerAgentSecret}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
               set -euo pipefail

               secret="$(openssl rand -hex 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${woodpeckerAgentSecret}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${woodpeckerAgentSecret}
          namespace: woodpecker
        spec:
          secretTemplates:
            - name: ${woodpeckerAgentSecret}
              type: Opaque
              stringData:
                agentSecret: "$secret"
        EOF
      '';
    };
  };
}
