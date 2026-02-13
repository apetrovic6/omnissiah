{charts, config, ... }:
let
  namespace = "pocketid";
  domain = config.noosphere.domain;
in
{
  helm.releases.pocket-id = {
    chart = charts.anza-labs.pocket-id;
    values = {

    };
  };

}
