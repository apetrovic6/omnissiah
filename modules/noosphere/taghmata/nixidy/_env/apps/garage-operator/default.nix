{ charts, ...} :
let
  namespace = "garage-operator";
in
{
  applications.garage-operator = {
    inherit namespace;
    createNamespace = true;

    helm.releases.garage-operator = {
      chart = charts.rajsinghtech.garage-operator;
      values = {
        replicaCount = 3;
      };
    };
  };
}
