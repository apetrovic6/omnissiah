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
      tags = ["base"];
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

    # General-purpose VM next to mars (tofunix manufactorum.nix): CI runners
    # and the always-on agent.
    ryza = {
      tags = ["base"];
      deploy.targetHost = "root@${hosts.ryza}";
      deploy.buildHost = "localhost";
    };

    cypramundi = {
      tags = [];
      deploy.targetHost = "root@${hosts.cypramundi}";
      deploy.buildHost = "localhost";
    };

    # The cluster. `taghmata` is every node, for `clan machines update --tags
    # taghmata`. `fabricator` and `skitarii` assign the roles of the same name
    # (clan.nix, stc/taghmata.nix): control plane and workloads.
    terra = {
      tags = ["base" "taghmata" "fabricator" "skitarii"];
      deploy.targetHost = "root@${hosts.terra}";
      deploy.buildHost = "localhost";
    };

    luna = {
      tags = ["base" "taghmata" "fabricator" "skitarii"];
      deploy.targetHost = "root@${hosts.luna}";
      deploy.buildHost = "localhost";
    };

    sol = {
      tags = ["base" "taghmata" "fabricator" "skitarii"];
      deploy.targetHost = "root@${hosts.sol}";
      deploy.buildHost = "localhost";
    };

    mars = {
      tags = ["base" "taghmata" "fabricator"];
      deploy.targetHost = "root@${hosts.mars}";
      deploy.buildHost = "localhost";
    };
  };
}
