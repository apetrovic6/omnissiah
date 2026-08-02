{...}: {
  inventory.machines = {
    phalanx = {
      tags = ["base" "workstation" "dev" "gaming"];
      deploy.targetHost = "root@192.168.1.71";
      deploy.buildHost =  "localhost";
    };

    enginseer = {
      tags = ["base" "laptop" "workstation" "dev" "gaming"];
      deploy.targetHost = "root@192.168.1.157";
      deploy.buildHost =  "localhost";
    };

    genetor = {
      machineClass = "darwin";
      deploy.targetHost = "root@192.168.1.109";
    };

    cerberus = {
      tags = ["base" "server"];
      deploy.targetHost = "root@192.168.1.105";
      deploy.buildHost = "localhost";
    };

    alfrost = {
      tags = [];
    };

    cypramundi = {
      tags = [];
      deploy.targetHost =  "root@152.53.34.16";
      deploy.buildHost =  "localhost";
    };

    terra = {
      tags = ["base" "k8s-base"];
      deploy.targetHost = "root@192.168.1.138";
      deploy.buildHost =  "localhost";
    };

    luna = {
      tags = ["base" "k8s-base" "k8s-server"];
      deploy.targetHost = "root@192.168.1.232";
      deploy.buildHost =  "localhost";
    };

    sol = {
      tags = ["base" "k8s-base" "k8s-server"];
      deploy.targetHost = "root@192.168.1.42";
      deploy.buildHost =  "localhost";
    };
  };
}
