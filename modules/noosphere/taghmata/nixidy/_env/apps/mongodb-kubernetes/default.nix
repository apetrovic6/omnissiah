{
  charts,
  pkgs,
  ...
}: let
    namespace = "mongodb";
in {
  applications.mongodb-kubernetes-operator= 
  {
    inherit namespace;
    createNamespace = true;

    helm.releases.mongodb-kubernetes-operator= {
      chart = charts.mongodb.mongodb-kubernetes;

      values = { };
    };
  };
}
