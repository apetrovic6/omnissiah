{
  config,
  charts,
  ...
}: let
  namespace = "karakeep";
  domain = config.noosphere.domain;
  sso = config.noosphere.sso;
  meiliSecret = "karakeep-meilisearch-secret";
in {
  applications.karakeep = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/karakeep-meilisearch-secret/karakeep-meilisearch-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/karakeep-secret/karakeep-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/karakeep-sso-secret/karakeep-sso-secret/value)
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
            "category" = "productivity";
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
              karakeep = {
                env = {
                  NEXTAUTH_URL = "https://karakeep.${domain}";
                  OAUTH_WELLKNOWN_URL = sso.wellKnownUrl;
                  OAUTH_SCOPE = "openid email profile";
                  OAUTH_PROVIDER_NAME = "Pocket ID";
                  OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING = true;
                };

                envFrom = [
                  {secretRef = {name = "karakeep-secret";};}
                  {secretRef = {name = "karakeep-oidc";};}
                  {secretRef = {name = meiliSecret;};}
                ];
              };
            };
          };
        };
      };
    };
  };
}
