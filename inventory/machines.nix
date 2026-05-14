{...}: {
  inventory.machines = {
    phalanx = {
      tags = ["base" "workstation" "dev" "gaming"];
      deploy.targetHost = "root@192.168.1.46";
    };

    enginseer = {
      tags = ["base" "laptop" "workstation" "dev" "gaming"];
      deploy.targetHost = "root@192.168.1.50";
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
    };

    luna = {
      tags = ["base" "k8s-base" "k8s-server"];
      deploy.targetHost = "root@192.168.1.232";
    };

    sol = {
      tags = ["base" "k8s-base" "k8s-server"];
      deploy.targetHost = "root@192.168.1.42";
    };
  };
}
