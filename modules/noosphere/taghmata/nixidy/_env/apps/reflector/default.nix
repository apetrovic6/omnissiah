{charts, ...}: let
  namespace = "reflector";
in {
  applications.reflector = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/barman-s3-secret-key/barman-s3-secret-key/value)
    ];

    helm.releases.reflector = {
      chart = charts.emberstack.reflector;
    };
  };
}
