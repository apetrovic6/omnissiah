# NAR signing key for the ncps binary cache.
#
# ncps will happily auto-generate a signing key when none is supplied, but the
# generated key is not recorded anywhere we control: if the volume or the row
# backing it is ever lost, the cache comes back with a *different* public key
# and every client that pinned the old one rejects everything it serves. So the
# key is minted here instead and handed to the chart via
# `config.signing.existingSecret`.
#
# Two outputs:
#   - ncps-signing-key      (non-secret) sops-encrypted SopsSecret, read into
#                           the ncps app with builtins.readFile. The data key
#                           must be `signing-key`; that name is hardcoded in
#                           the chart's statefulset (subPath: signing-key).
#   - ncps-signing-key.pub  (non-secret) the matching public key, in
#                           nix.settings.trusted-public-keys format, so clients
#                           can be pointed at it without a round trip through
#                           the cluster.
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  domain = config.noosphere.domain;
  fileName = "ncps-signing-key";
  pubFile = "ncps-signing-key.pub";
  namespace = "ncps";
  # Nix binary cache keys are named `<host>-<n>`; the suffix is what lets you
  # rotate by adding a second key while clients still trust the first.
  keyName = "ncps.${domain}-1";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${fileName} = {
      share = true;

      files.${fileName}.secret = false;
      files.${pubFile}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.nix pkgs.sops];

      script = ''
        set -euo pipefail

        # Produces the `<name>:<base64>` pair that ncps' --cache-secret-key-path
        # expects; it is the same format `nix store sign` uses.
        nix-store --generate-binary-cache-key \
          "${keyName}" "$TMPDIR/secret" "$out/${pubFile}"

        secret_key="$(cat "$TMPDIR/secret")"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${fileName}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${fileName}
          namespace: ${namespace}
        spec:
          secretTemplates:
            - name: ${fileName}
              type: Opaque
              stringData:
                signing-key: "$secret_key"
        EOF
      '';
    };
  };
}
