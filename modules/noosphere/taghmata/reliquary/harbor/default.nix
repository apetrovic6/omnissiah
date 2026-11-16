{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      harbor-admin-password-secret = {
        namespace = "harbor";
        random.secret = "-hex 16";
        data.HARBOR_ADMIN_PASSWORD = "$secret";
      };

      harbor-secret-secret-key = {
        namespace = "harbor";
        random.secret = "-hex 8";
        data.secretKey = "$secret";
      };

      harbor-job-service-secret = {
        namespace = "harbor";
        random.secret = "-hex 8";
        data.JOBSERVICE_SECRET = "$secret";
      };

      harbor-registry-http-secret = {
        namespace = "harbor";
        random.secret = "-hex 8";
        data.REGISTRY_HTTP_SECRET = "$secret";
      };

      harbor-redis-password-secret = {
        namespace = "harbor";
        random.secret = "-hex 16";
        data.REDIS_PASSWORD = "$secret";
      };

      harbor-registry-credentials-secret = {
        namespace = "harbor";
        setup = ''
          user="harbor"
          pwd="$(openssl rand -base64 32 | tr -d '\n' | head -c 32)"
          # Generates: user:$2y$...
          htpwd="$(htpasswd -nbB "$user" "$pwd")"
        '';
        data = {
          REGISTRY_PASSWD = "$pwd";
          REGISTRY_HTPASSWD = "$htpwd";
        };
        # htpasswd comes from apache httpd utils
        runtimeInputs = [pkgs.openssl pkgs.apacheHttpd];
      };

      pg-harbor-postgres-secret = {
        namespace = "harbor";
        labels."cnpg.io/reload" = "true";
        prompts.pg-harbor-username = {
          description = "DB Username";
          type = "line";
          var = "username";
        };
        prompts.pg-harbor-password = {
          description = "DB Password";
          var = "password";
        };
        data = {
          username = "$username";
          password = "$password";
        };
      };

      harbor-core-secret = {
        namespace = "harbor";
        random = {
          # 16 chars required
          core_secret = "-hex 8";
          # 32 chars required
          xsrf_key = "-hex 16";
        };
        # Token service keypair (does NOT need to be Let's Encrypt)
        setup = ''
          tmp="$(mktemp -d)"
          trap 'rm -rf "$tmp"' EXIT

          openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$tmp/tls.key"
          openssl req -new -x509 -sha256 -days 3650 \
            -key "$tmp/tls.key" \
            -subj "/CN=harbor-token-service" \
            -out "$tmp/tls.crt"
        '';
        data = {
          secret = "$core_secret";
          CSRF_KEY = "$xsrf_key";
          "tls.crt" = ''$(cat "$tmp/tls.crt")'';
          "tls.key" = ''$(cat "$tmp/tls.key")'';
        };
      };
    };
  };
}
