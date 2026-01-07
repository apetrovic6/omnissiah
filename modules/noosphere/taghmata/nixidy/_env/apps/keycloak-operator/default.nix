{pkgs, ...}:
let
  namespace = "keycloak";
  keycloakVersion = "26.5.0";
  keycloakCrds1 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${keycloakVersion}/kubernetes/keycloaks.k8s.keycloak.org-v1.yml";
    hash = "";
  };
in
 {
   application.keycloak = {
      inherit namespace;
      createNamespace = true;

      yamls = [
        (builtins.readFile keycloakCrds1)
      ];
   };

}
