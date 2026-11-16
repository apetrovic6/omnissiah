{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      garage-backup-ui-jwt-token-secret = {
        namespace = "garage-operator";
        # Written to a file first so the PEM keeps its line breaks.
        setup = ''
          tmp="$(mktemp -d)"
          trap 'rm -rf "$tmp"' EXIT
          openssl genpkey -algorithm ED25519 -out "$tmp/jwt-key.pem"
        '';
        data."jwt-key.pem" = ''$(cat "$tmp/jwt-key.pem")'';
        runtimeInputs = [pkgs.openssl];
      };

      garage-backup-ui-oidc-secret = {
        namespace = "garage-operator";
        prompts.client-secret.description = "Keycloak Client Secret for Garage Backup UI";
        data.client-secret = "$client_secret";
      };
    };
  };
}
