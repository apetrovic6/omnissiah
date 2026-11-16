# The pilot's session-cookie key (template ADR 0029): 32 random bytes, base64, which is what
# the service's `auth.cookie_key` expects. Generated, never typed; rotating it signs everyone
# out. The cerberus deployment has its own key (machines/cerberus/pilot.nix).
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  # The generator is named for the cluster: cerberus's own is `pilot-cookie-key`.
  generator = "pilot-k8s-cookie-key";
  pilotCookieKey = "pilot-cookie-key";
in {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators.${generator} = {
      share = true;

      files.${generator}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.sops pkgs.openssl];

      script = ''
        set -euo pipefail

        key="$(openssl rand -base64 32)"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${generator}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${pilotCookieKey}
          namespace: pilot
        spec:
          secretTemplates:
            - name: ${pilotCookieKey}
              type: Opaque
              stringData:
                cookie-key: "$key"
        EOF
      '';
    };
  };
}
