{...}: let
  inherit (import ../modules/cartographa/_chart.nix) hosts;
in {
  inventory.machines = {
    phalanx = {
      tags = ["base" "workstation" "dev" "gaming"];
      deploy.targetHost = "root@${hosts.phalanx}";
      deploy.buildHost = "localhost";
    };

    enginseer = {
      tags = ["base" "laptop" "workstation" "dev" "gaming"];
      deploy.targetHost = "root@${hosts.enginseer}";
      deploy.buildHost = "localhost";
    };

    genetor = {
      machineClass = "darwin";
      deploy.targetHost = "root@${hosts.genetor}";
    };

    cerberus = {
      tags = ["base" "server"];
      deploy.targetHost = "root@${hosts.cerberus}";
      deploy.buildHost = "localhost";
    };

    alfrost = {
      tags = [];

      deploy.targetHost = "root@${hosts.alfrost}";
      deploy.buildHost = "localhost";
    };

    servitor = {
      tags = ["base"];
      deploy.targetHost = "root@${hosts.servitor}";
      deploy.buildHost = "localhost";
    };

    cypramundi = {
      tags = [];
      deploy.targetHost = "root@${hosts.cypramundi}";
      deploy.buildHost = "localhost";
    };

    terra = {
      tags = ["base"];
      deploy.targetHost = "root@${hosts.terra}";
      deploy.buildHost = "localhost";
    };

    luna = {
      tags = ["base"];
      deploy.targetHost = "root@${hosts.luna}";
      deploy.buildHost = "localhost";
    };

    sol = {
      tags = ["base"];
      deploy.targetHost = "root@${hosts.sol}";
      deploy.buildHost = "localhost";
    };

    mars = {
      tags = ["base"];
      deploy.targetHost = "root@${hosts.mars}";
      deploy.buildHost = "localhost";
    };
  };
}
