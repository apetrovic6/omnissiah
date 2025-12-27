{charts, ...}: {
  applications.cloudnativepg = let
    namespace = "cnpg-system";
  in {
    inherit namespace;
    createNamespace = true;

    helm.releases.cloudnative-pg = {
      chart = charts.cloudnative-pg.cloudnative-pg;
    };
  };
}
