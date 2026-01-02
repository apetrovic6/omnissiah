{
  config,
  charts,
  ...
}: let
  namespace = "karakeep";
  domain = config.nooshpere.domain;
in {
  applications.karakeep = {
    inherit namespace;
    createNamespace = true;

    helm.releases.karakeep = {
      chart = charts.karakeep-app.karakeep;

      values = {
        applicationHost = "karakeep.${domain}";
        controllers = {
          containers = {
            karakeep = {
              envFrom = [
                {name = "karakeep-secret";}
                {name = "karakeep-meilesearch-secret";}
              ];
            };
          };

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
        };
      };
    };
  };
}
