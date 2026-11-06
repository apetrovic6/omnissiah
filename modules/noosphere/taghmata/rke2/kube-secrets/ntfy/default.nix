# ntfy access control for the homelab alert topic, plus the cluster side of it.
#
# ntfy runs on cerberus (machines/cerberus/ntfy.nix -> modules/noosphere/vox/ntfy.nix,
# https://ntfy.<LAB_DOMAIN>). Alertmanager (observability, in-cluster) publishes to
# it. Both sides come from this one clan var, so nothing is copied by hand -- the
# same inversion kube-secrets/memos uses for a service that lives outside the cluster.
#
# Two outputs:
#   - ntfy.env          (secret) EnvironmentFile for ntfy-sh on cerberus. ntfy reads
#                       its config from the environment as well as from server.yml
#                       (NTFY_AUTH_USERS / NTFY_AUTH_ACCESS / NTFY_AUTH_TOKENS), which
#                       is the only way to declare users and a token without them
#                       landing in the nix store: services.ntfy-sh renders `settings`
#                       with pkgs.formats.yaml into a world-readable derivation, and
#                       the module's own `environmentFile` documentation names exactly
#                       this use ("pass secrets such as creating declarative users or
#                       token without putting them in the Nix store").
#   - alertmanager-ntfy (non-secret) sops-encrypted SopsSecret in observability, read
#                       into the prometheus-grafana app with builtins.readFile. The
#                       operator mounts it at /etc/alertmanager/secrets/alertmanager-ntfy/
#                       and Alertmanager reads the token from
#                       .../alertmanager-ntfy/token (http_config.authorization).
#
# ACL shape: the Alertmanager credential is write-only on the topic -- it can publish
# and nothing else. The phone account is read-only. Everything else is denied by
# `auth-default-access: deny-all` in machines/cerberus/ntfy.nix.
#
# Generate with:
#   clan vars generate cerberus --generator ntfy-access
# Re-running it with --regenerate rotates the passwords and both tokens: after that,
# redeploy cerberus (the ACLs change) and re-render + push the cluster manifests
# (nix develop -c nixidy switch .#prod), because the token the cluster holds must be
# the same value the server accepts. The phone's credentials change too, so they have
# to be pasted into the app again.
{config, ...}: let
  ageKey = config.noosphere.agePublicKey;
  generatorName = "ntfy-access";
  envFile = "ntfy.env";
  # SopsSecret name == the Secret it produces == the directory name the operator
  # mounts under /etc/alertmanager/secrets/.
  secretName = "alertmanager-ntfy";
  namespace = "observability";
  topic = "homelab-alerts";
  publisherUser = "alertmanager";
  readerUser = "apetrovic";
in {
  flake.nixosModules.noosphere = {pkgs, ...}: {
    clan.core.vars.generators.${generatorName} = {
      share = true;

      files.${envFile} = {
        secret = true;
        mode = "0400";
        # ntfy reads its users and tokens once, at start. Without this, a deploy
        # that only rotates the var leaves the server on the old credentials
        # (seen 2026-11-06: the phone got "not authorized" with the new
        # password until ntfy-sh was restarted by hand).
        restartUnits = ["ntfy-sh.service"];
      };

      files.${secretName}.secret = false;

      # The phone account's plaintext password. ntfy.env only carries its bcrypt
      # hash, and the ntfy apps log in with username + password (they don't take an
      # empty username with a token). Not deployed anywhere: read it with
      #   clan vars get cerberus ntfy-access/reader-password
      files.reader-password = {
        secret = true;
        deploy = false;
      };

      runtimeInputs = [
        pkgs.coreutils
        pkgs.openssl
        pkgs.sops
        pkgs.ntfy-sh
        (pkgs.python3.withPackages (ps: [ps.bcrypt]))
      ];

      script = ''
        set -euo pipefail

        # Hex only, like everywhere else here: these values land in an
        # EnvironmentFile line and in a YAML heredoc, so no character in them may
        # need quoting.
        publisher_password="$(openssl rand -hex 24)"
        reader_password="$(openssl rand -hex 24)"

        # The token comes from ntfy itself. ntfy validates the format of a provisioned
        # token and rejects anything else outright -- a hand-minted `tk` + 64 hex
        # string fails at server start with:
        #   invalid auth-tokens: ... token ... invalid, use 'ntfy token generate'
        # and the valid shape is tk_ + 26 characters (tk_w24ooikiip0lvzm3n6p2vy3dwbpuo).
        # `token generate` is documented as "generates the token value, but does not
        # persist it anywhere", which is exactly what a var wants: the value is minted
        # here, declared to the server through NTFY_AUTH_TOKENS, and handed to the
        # cluster through the SopsSecret below, so a rotation is one command and both
        # sides always agree.
        publisher_token="$(ntfy token generate)"
        reader_token="$(ntfy token generate)"

        # Hashes have to be minted here because `ntfy user hash` -- the command ntfy's
        # own config comments point at -- is interactive-only: it prompts for the
        # password *and a confirmation* through the terminal, and in a non-interactive
        # generator it dies with "password: inappropriate ioctl for device". Python's
        # bcrypt produces $2b$10$..., which is the same algorithm ntfy verifies with
        # (it emits $2a$10$... itself) and which this server accepted: with a hash built
        # this way, a correct password gets 200/403-by-ACL and a wrong one gets 401.
        hash_of() {
          python3 -c 'import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=10)).decode())' "$1"
        }
        publisher_hash="$(hash_of "$publisher_password")"
        reader_hash="$(hash_of "$reader_password")"

        # Single quotes around each value: a bcrypt hash contains $ and ., and the
        # shell must not touch them. ntfy reads these as comma-separated lists.
        #
        # The reader gets a password AND a token, because they cover different paths:
        # a subscription from the phone needs something the app can attach to a GET
        # (the apps take an access token per connection; basic-auth is for the web UI
        # and for curl), and a token is also what a UnifiedPush poll carries, where
        # there is no interactive login at all.
        cat > "$out/${envFile}" <<EOF
        NTFY_AUTH_USERS='${publisherUser}:''${publisher_hash}:user,${readerUser}:''${reader_hash}:user'
        NTFY_AUTH_ACCESS='${publisherUser}:${topic}:wo,${readerUser}:${topic}:ro'
        NTFY_AUTH_TOKENS='${publisherUser}:''${publisher_token}:Alertmanager write token for ${topic},${readerUser}:''${reader_token}:Read token for ${readerUser} on ${topic}'
        EOF

        printf '%s' "$reader_password" > "$out/reader-password"

        # The reader's password (reader-password, not deployed) and token (in the
        # env file) are never in the nix store, never in a rendered manifest, and
        # never printed by anything here.

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretName}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${secretName}
          namespace: ${namespace}
        spec:
          secretTemplates:
            - name: ${secretName}
              type: Opaque
              stringData:
                token: "$publisher_token"
        EOF
      '';
    };
  };
}
