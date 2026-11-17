{...}: {
  nixidy.envs.prod.apps.reflector = {charts, ...}: let
    namespace = "reflector";
  in {
    applications.reflector = {
      inherit namespace;
      createNamespace = true;

      helm.releases.reflector = {
        chart = charts.emberstack.reflector;
      };
    };
  };
}
