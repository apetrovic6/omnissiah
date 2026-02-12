{ charts, ...}:
let
 namespace = "dagger";
in
{
applications.dagger = {
  inherit namespace;
  createNamespace = true;

  helm.releases.dagger = {
    chart = charts.dagger-helm.dagger-helm;
  };
};

}
