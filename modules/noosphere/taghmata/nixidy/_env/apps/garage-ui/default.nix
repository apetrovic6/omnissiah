{charts, ...}: let
  namespace = "garage";
in {
  applications.garage-ui = {
    inherit namespace;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-ui-admin-token/garage-ui-admin-token/value)
    ];

    helm.releases.garage-ui = {
      chart = charts.noooste.garage-ui;

      values = {
        config = {
          garage = {
            endpoint = "http://garage:3900";
            admin_endpoint = "http://garage-admin:3903";
            admin_token = "";
            region = "imperium";
          };

          existingSecret = {
            name = "garage-ui-admin-token";
            key = "admin-token";
          };
        };
      };
    };
  };
}
