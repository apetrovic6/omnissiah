{...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    clusterAgeRecipient = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
  in {
    clan.core.vars.generators.cloudflare-api-token-secret = {
      # If you want the same token shared across machines:
      share = true;

      # Prompt once (hidden); don't store the plaintext token in the repo.
      prompts.cloudflareToken.description = "Cloudflare API token (for cert-manager DNS01)";
      prompts.cloudflareToken.type = "hidden";
      prompts.cloudflareToken.persist = false;

      # IMPORTANT: store the *encrypted YAML* in git (not as a clan secret),
      # because ArgoCD needs to read/apply it.
      files."cloudflare-api-token.sopssecret.yaml".secret = false;

      runtimeInputs = [pkgs.sops pkgs.coreutils pkgs.gnused];

      script = ''
              set -euo pipefail

              tmp="$(mktemp)"
              trap 'rm -f "$tmp"' EXIT

              # Build plaintext SopsSecret YAML (token inserted as a YAML block scalar)
              cat > "$tmp" <<'YAML'
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: cloudflare-api-token
          namespace: cert-manager
        spec:
          secretTemplates:
            - name: cloudflare-api-token-secret
              type: Opaque
              stringData:
                api-token: |
        YAML

              # Indent token so it's valid YAML under the block scalar
              sed 's/^/          /' < "$prompts/cloudflareToken" >> "$tmp"

              # Encrypt for the cluster recipient (operator will decrypt in-cluster)
              sops --encrypt --age "${clusterAgeRecipient}" "$tmp" > "$out/cloudflare-api-token.enc.yaml"
      '';
    };
  };
}
