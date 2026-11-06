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
  uploadAuth = "ncps-upload-auth";
  uploadUser = "forgejo-runner";
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

    # Basic auth on ncps' /upload, so only the Forgejo runners can reach the
    # upload endpoint at all. ncps also rejects an upload not signed by the CI
    # key; this closes the endpoint itself (uploads of junk, load on it).
    #   - netrc               (secret) the runners' credential, which nix sends
    #                         through nix.settings.netrc-file (modules/rites/
    #                         forgejo-runner.nix).
    #   - ncps-upload-auth    (non-secret) sops-encrypted SopsSecret with the
    #                         bcrypt htpasswd line, read by Traefik's basicAuth
    #                         middleware in the ncps app. Traefik reads the
    #                         `users` key.
    clan.core.vars.generators.${uploadAuth} = {
      share = true;

      files.netrc.secret = true;
      files.${uploadAuth}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.openssl pkgs.apacheHttpd pkgs.sops];

      script = ''
        set -euo pipefail

        # Hex, so nothing in it needs quoting in a netrc or an htpasswd line.
        password="$(openssl rand -hex 32)"

        printf 'machine ncps.${domain}\nlogin ${uploadUser}\npassword %s\n' "$password" > "$out/netrc"

        users="$(htpasswd -nbB ${uploadUser} "$password")"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${uploadAuth}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${uploadAuth}
          namespace: ${namespace}
        spec:
          secretTemplates:
            - name: ${uploadAuth}
              type: Opaque
              stringData:
                users: "$users"
        EOF
      '';
    };
  };
}
