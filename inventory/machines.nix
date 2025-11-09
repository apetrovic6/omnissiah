{...}:
{
  inventory.machines = {
    # Define machines here.
    enginseer = {
      tags = [ "base" "laptop" "workstation" "dev" ];
      deploy.targetHost = "root@192.168.1.50";
    };

    genetor = {
      machineClass = "darwin";
    };
  };
}
