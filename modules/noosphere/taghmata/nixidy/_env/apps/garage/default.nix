{
  charts,
  lib,
  ...
}: let
  namespace = "garage";
  domain = "noosphere.uk";
in {
  applications.garage = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-rpc-secret/garage-rpc-secret/value)
      # ''

      #   apiVersion: cert-manager.io/v1
      #   kind: Certificate
      #   metadata:
      #     name: garage-tls
      #     namespace: garage
      #   spec:
      #     secretName: garage-tls
      #     issuerRef:
      #       kind: ClusterIssuer
      #       name: letsencrypt-cloudflare
      #     dnsNames:
      #       - s3.${domain}
      #       - web.${domain}
      #       - "*.s3.${domain}"
      #       - "*.web.${domain}"
      # ''
    ];

    helm.releases.garage = {
      chart = charts.deuxfleurs.garage;

      values = {
        replicationFactor = 2;
        existingRpcSecret = "garage-rpc-secret";
        s3 = {
          api = {
            region = "imperium";
            rootDomain = "s3.${domain}";
          };
          web = {
            rootDomain = "web.${domain}";
          };
        };
        persistence = {
          meta = {
            storageClass = "synology-nfs";
            size = "20Gi";
          };
          data = {
            storageClass = "synology-nfs";
            size = "300Gi";
          };
        };
        ingress = {
          s3 = {
            api = {
              enabled = true;
              className = "traefik";
              annotations = {
                "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
              };
              hosts = [
                {
                  host = "s3.garage.${domain}";
                  paths = [
                    {
                      path = "/";
                      pathType = "Prefix";
                    }
                  ];
                }

                {
                  host = "*.s3.garage.${domain}";
                  paths = [
                    {
                      path = "/";
                      pathType = "Prefix";
                    }
                  ];
                }
              ];
              tls = [
                {
                  secretName = "garage-tls";
                  hosts = ["s3.garage.${domain}" "*.s3.garage.${domain}"];
                }
              ];
            };
          };
          web = {
            enabled = true;
            className = "traefik";
            annotations = {
              "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
            };
            hosts = [
              {
                host = "web.garage.${domain}";
                paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                  }
                ];
              }

              {
                host = "*.web.garage.${domain}";
                paths = [
                  {
                    path = "/";
                    pathType = "Prefix";
                  }
                ];
              }
            ];
            tls = [
              {
                secretName = "garage-tls";
                hosts = ["web.garage.${domain}" "*.web.garage.${domain}"];
              }
            ];
          };
        };
      };
    };
  };
}
