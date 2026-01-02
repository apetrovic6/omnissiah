{
  charts,
  config,
  ...
}: let
  namespace = "garage";
  domain = config.noosphere.domain;
in {
  applications.garage-ui = {
    inherit namespace;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-ui-admin-token/garage-ui-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-ui-jwt-token-secret/garage-ui-jwt-token-secret/value)

      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: garage-ui-tls
          namespace: ${namespace}
        spec:
          secretName: garage-ui-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - ui.garage.${domain}
      ''
    ];

    resources.ingresses.garage-ui-ip-root = {
      metadata = {
        inherit namespace;

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "garage-ui-tls";
            hosts = ["ui.garage.${domain}"];
          }
        ];

        rules = [
          {
            host = "ui.garage.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "garage-ui";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };

    helm.releases.garage-ui = {
      chart = charts.noooste.garage-ui;

      values = {
        config = {
          garage = {
            endpoint = "http://garage:3900";
            admin_endpoint = "http://garage-admin:3903";
            region = "garage";
          };

          existingSecret = {
            name = "garage-ui-admin-token";
            key = "admin-token";
          };

          cors = {
            enabled = true;
            allowed_origins = ["https://ui.garage.${domain}"];
          };

          serviceMonitor = {
            enabled = true;
            interval = "30s";
            path = "/api/v1/monitoring/metrics";
            labels = {prometheus = "kube-prometheus";};
          };

          auth = {
            jwt_private_key_secret = {
              name = "garage-ui-jwt-token-secret";
              key = "jwt-key.pem";
            };
          };
        };
      };
    };
  };
}
