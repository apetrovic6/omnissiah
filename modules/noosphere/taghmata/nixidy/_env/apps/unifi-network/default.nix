{charts, ...}:
let
  namespace = "unifi";
in
{
applications.unifi-network = {
inherit namespace;
createNamespace = true;

};

}
