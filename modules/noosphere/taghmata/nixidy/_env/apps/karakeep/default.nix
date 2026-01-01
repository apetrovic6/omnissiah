{config, pkgs, ...}:
let
  namespace = "karakeep";
  domain = config.nooshpere.domain.domain;
in
 {
    applications.karakeep = {
      inherit namespace;
      createNamespace = true;

      kustomization = {
        src = pkgs.fetchFromGitHub {
          owner = "karakeep-app";
          repo = "karakeep";
          rev = "0.30.0";
          hash =  "";
        };

        path = "kubernetes";
      };
    };
}
