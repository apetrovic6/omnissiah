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

        ingress = {
          karakeep.annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
            "glance/name" = "Karakeep";
            "glance/icon" = "di:karakeep";
            "glance/url" = "https://karakeep.${domain}";
            "glance/description" = "Bookmark Management";
            "glance/id" = "karakeep";
            "glance/parent" = "karakeep";
            "category" = "utils";
          };

          karakeep.tls = [
            {
              secretName = "karakeep-tls";
              hosts = ["karakeep.${domain}"];
            }
          ];
        };
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
