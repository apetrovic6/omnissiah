{
  charts,
  config,
  ...
}: let
  namespace = "reflector";
  domain = config.noosphere.domain;
in {
  applications.reflector = {
    inherit namespace;
    createNamespace = true;

    helm.releases.reflector = {
      chart = charts.emberstack.reflector;
    };
  };
}
