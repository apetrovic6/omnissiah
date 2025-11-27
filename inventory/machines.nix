{...}: {
  inventory.machines = {
    # Define machines here.
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
      deploy.targetHost = "root@192.168.122.170";
    };
  };
}
