{...}: {
  flake.nixosModules.vox = {
    lib,
    config,
    pkgs,
    ...
  }: let
    domain = "ugalabugala.org";
    matrixDomain = "matrix.${domain}";
    clientConfig = {
      "m.homeserver".base = "https://${matrixDomain}";
      "m.identity_server" = {};
    };

    serverConfig = {
      "m.server" = "${matrixDomain}:443";
    };

    mkWellKnown = data: ''
      default_type application/json;
      add_header Access-Control-Allow-Origin *;
      return 200 '${builtins.toJSON data}';
    '';
  in {
    clan.core.vars.generators.matrix-registration-secret = {
      files."registration_shared_secret" = {
        secret = true;
        owner = "matrix-synapse";
        mode = "0400";
      };

      runtimeInputs = [pkgs.openssl];

      script = ''
        openssl rand -hex 32 > "$out/registration_shared_secret"
      '';
    };

    services.matrix-synapse = {
      enable = true;

      extraConfigFiles = [
        (pkgs.writeText "matrix-registration-secret.yaml" ''
          registration_shared_secret_path: "${config.clan.core.vars.generators.matrix-registration-secret.files."registration_shared_secret".path}"
        '')
      ];

      settings = {
        server_name = domain;
        public_baseurl = "https://${matrixDomain}";
        serve_server_wellknown = true;
        listeners = [
          {
            port = 8008;
            bind_addresses = ["127.0.0.1"];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [
              {
                names = ["client" "federation"];
                compress = true;
              }
            ];
          }
        ];

        database = {
          name = "psycopg2";
          allow_unsafe_locale = true;
          args = {
            user = "matrix-synapse";
            database = "matrix-synapse";
            host = "/run/postgresql";
          };
        };

        max_upload_size = "100M";
        url_preview_enabled = true;
        enable_registration = true;
        registration_requires_token = true;
        enable_metrics = false;

        trusted_key_servers = [{server_name = "matrix.org";}];
      };
    };

    # services.nginx.enable = true;
    # services.nginx.virtualHosts.${domain} = {
    #   enableACME = true;
    #   forceSSL = true;
    #   locations. "= /.well-known/matrix/server".extraConfig = mkWellKnown serverConfig;
    #   locations. "= /.well-known/matrix/client".extraConfig = mkWellKnown clientConfig;
    # };

    # services.nginx.virtualHosts.${matrixDomain} = {
    #   enableACME = true;
    #   forceSSL = true;
    #   locations."/" = {
    #     proxyPass = "http://127.0.0.1:8008";
    #     extraConfig = ''
    #       proxy_set_header X-Forwarded-For $remote_addr;
    #       proxy_set_header x-Forwarded-Proto $scheme;
    #       proxy_set_header Host $host;
    #       client_max_body_size 100M;
    #       '';
    #   };
    # };

    # networking.firewall.allowedTCPPorts = [8448];
  };
}
