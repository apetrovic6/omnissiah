{charts, ...}: let
  namespace = "garage";
  domain = "noosphere.uk";
in {
  applications.garage-ui = {
    inherit namespace;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-ui-admin-token/garage-ui-admin-token/value)
    ];

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

          ingress = {
            enabled = true;
            className = "traefik";
            annotations = {
              "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
            };

            hosts = [
              {
                host = "ui.garage.${domain}";
                paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                  }
                ];

                tls = [
                  {
                    secretName = "garage-ui-tls";
                    hosts = ["ui.garage.${domain}"];
                  }
                ];
              }
            ];
          };

          serviceMonitor = {
            enabled = true;
            interval = "30s";
            path = "/api/v1/monitoring/metrics";
            labels = {prometheus = "kube-prometheus";};
          };
        };
      };
    };
  };
}
