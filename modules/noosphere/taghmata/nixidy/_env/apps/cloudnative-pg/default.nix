{
  charts,
  pkgs,
  ...
}: let
  barmanVersion = "0.10.0";
  barmanManifest = pkgs.fetchurl {
    url = "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${barmanVersion}/manifest.yaml";
    hash = "sha256-9yjeqQqt490v60xLOTX6dLyHQwdjU8lwY1kbHQrUuKQ=";
  };
in {
  applications.barman-cloud = {
    namespace = "cnpg-system";
    yamls = [
      (builtins.readFile barmanManifest)
    ];
  };

  applications.cloudnativepg = let
    namespace = "cnpg-system";
  in {
    inherit namespace;
    createNamespace = true;

    helm.releases.cloudnative-pg = {
      chart = charts.cloudnative-pg.cloudnative-pg;
    };
  };
}
