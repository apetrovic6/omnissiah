{
  charts,
  lib,
  ...
}: let
  namespace = "garage";
  domain = "noosphere.uk";
in {
  applications.garage = {
    inherit namespace;
    createNamespace = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-rpc-secret/garage-rpc-secret/value)
    ];

    helm.releases.garage = {
      chart = charts.deuxfleurs.garage;

      values = {
        replicationFactor = 2;
        existingRpcSecret = "garage-rpc-secret";
        s3 = {
          api = {
            region = "imperium";
            rootDomain = ".s3.${domain}";
          };
          web = {
            rootDomain = ".web.${domain}";
          };
        };
        persistence = {
          meta = {
            storageClass = "synology-nfs";
          };
          data = {
            storageClass = "synology-nfs";
          };
        };
        # ingress = {
        #   s3 = {

        #   };
        # };
      };
    };
  };
}
