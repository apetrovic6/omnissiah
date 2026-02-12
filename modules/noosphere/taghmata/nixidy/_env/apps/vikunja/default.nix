{charts, config, ...}:
let
 namespace = "vikunja";
 domain = config.noosphere.domain;
 in
 {
applications.vikunja = {
  inherit namespace;
  createNamespace = true;

  helm.releases.vikunja = {
    chart = charts.go-vikunja;
  };
};

}
