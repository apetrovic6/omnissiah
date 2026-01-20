{charts, ...}: let
  namespace = "percona-mongodb";
in {
  applications.percona-mongodb-operator = {
    inherit namespace;
    createNamespace = true;

    helm.releases.percona-server-mongodb-operator = {
      chart = charts.percona.psmdb-operator;

      values = {
        # Watch all namespaces
        watchNamespace = "unifi-controller";

        # Enable debug logging if needed
        logLevel = "INFO";

        # Resource limits for operator
        resources = {
          limits = {
            cpu = "500m";
            memory = "512Mi";
          };
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
        };
      };
    };
  };
}
