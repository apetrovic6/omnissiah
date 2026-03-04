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
    };

    cerberus = {
      tags = ["base" "server"];
      deploy.targetHost = "root@192.168.1.191";
      deploy.buildHost = "localhost";
    };

    alfrost = {
      tags = [];
    };

    cypramundi = {
      tags = [];
    };

    terra = {
      tags = ["base" "k8s-base"];
      deploy.targetHost = "root@192.168.1.48";
    };

    luna = {
      tags = ["base" "k8s-base" "k8s-server"];
      deploy.targetHost = "root@192.168.1.59";
    };

    sol = {
      tags = ["base" "k8s-base" "k8s-server"];
      deploy.targetHost = "root@192.168.1.126";
    };
  };
}
