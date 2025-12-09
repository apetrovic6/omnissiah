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

    sol = {
      tags = ["base" "server"];
      # deploy.targetHost = "root@192.168.1.81";
      deploy.targetHost = "root@192.168.71.146";
    };

    terra = {
      tags = ["base" "k8s-server"];
      deploy.targetHost = "root@192.168.71.62";
    };

    luna = {
      tags = ["base" "k8s-server"];
      # deploy.targetHost = "root@192.168.71.62";
    };
  };
}
