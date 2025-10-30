{...}:
{
  inventory.machines = {
    # Define machines here.
    enginseer = {
      tags = [ "base" "laptop" ];
      deploy.targetHost = "root@192.168.1.50";
    };
  };
}
