{charts, ...}:
let
  namespace = "garage";
in

 {
  applications.garage = {
    inherit namespace;
    createNamespace = true;

    helm.releases.garage = {
      chart = charts.deuxfleurs.garage;

      values = {


      };
    };
  };
}
