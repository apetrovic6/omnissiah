{
  config,
  charts,
  ...
}: let
  namespace = "karakeep";
  domain = config.noosphere.domain;
  meiliSecret = "karakeep-meilisearch-secret";
in {
  applications.karakeep = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/karakeep-meilisearch-secret/karakeep-meilisearch-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/karakeep-secret/karakeep-secret/value)

      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: karakeep-tls
          namespace: ${namespace}
        spec:
          secretName: karakeep-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - karakeep.${domain}
      ''
    ];

    helm.releases.karakeep = {
      chart = charts.karakeep-app.karakeep;

      values = {
        applicationHost = "karakeep.${domain}";

        secrets = {
          karakeep.enabled = false;
          meilesearch.enabled = false;
        };

        meilisearch.auth.existingMasterKeySecret = meiliSecret;

        ingress.karakeep.tls = [
          {
            secretName = "karakeep-tls";
            hosts = ["karakeep.${domain}"];
          }
        ];

        controllers = {
          karakeep = {
            statefulset = {
              volumeClaimTemplates = [
                {
                  name = "data";
                  accessMode = "ReadWriteOnce";
                  size = "2Gi";
                  storageClass = "longhorn";
                  globalMounts = [{path = "/data";}];
                }
              ];
            };

            containers = {
              karakeep.envFrom = [
                {secretRef = {name = "karakeep-secret";};}
                {secretRef = {name = meiliSecret;};}
              ];
            };
          };
        };
      };
    };
  };
}
