{charts, ...}: {
  applications.alloy = {
    namespace = "alloy";
    createNamespace = true;
    helm.releases.alloy = {
      chart = charts.grafana.alloy-operator;
      includeCRDs = true;

      values = {
        replicaCount = 3;
      };
    };

    yamls = [
      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: alloy-tls
          namespace: observability
        spec:
          secretName: alloy-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - alloy.noosphere.uk
      ''
    ];

    resources.ingresses.alloy-ip-root = {
      metadata = {
        namespace = "alloy";

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "alloy-tls";
            hosts = ["alloy.noosphere.uk"];
          }
        ];

        rules = [
          {
            host = "alloy.noosphere.uk";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "default-alloy";
                  port.number = 12345;
                };
              }
            ];
          }
        ];
      };
    };

    resources.alloys.default = {
      metadata = {
        namespace = "observability";
      };

      spec = {
        configMap = {
          content = ''
            discovery.kubernetes "operator_pods" {
              role = "pod"

              namespaces {
                names = ["operator"]
              }

              selectors {
                role  = "pod"
                label = "app.kubernetes.io/name=alloy-operator"
              }
            }

            prometheus.exporter.self "default" {}

            prometheus.scrape "default" {
              targets    = prometheus.exporter.self.default.targets
              forward_to = [prometheus.remote_write.local_prom.receiver]
            }

             prometheus.remote_write "local_prom" {
               endpoint {
                 url = "http://prometheus-prometheus.observability.svc:9090/api/v1/write"
               }
             }
          '';
        };

        # alloy = {
        #   clustering = {
        #     enabled = true;
        #     name = "omnissiah";
        #   };
        # };
        # controller = {
        #   replicas = 3;
        #   type = "daemonset";
        #   # enableStatefulSetAutoDeletePVC = true;
        #   # volumeClaimTemplates = {
        #   #   metadata = ["alloy-wal"];
        #   # };
        # };

        # ingress = {
        #   enabled = true;
        #   ingressClassName = "traefik";
        #   hosts = ["alloy.noosphere.uk"];
        #   tls = ["alloy-tls"];
        # };
      };
    };
  };
}
