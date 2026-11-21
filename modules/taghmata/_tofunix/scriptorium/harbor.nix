# Harbor: the pull-through caches for Docker Hub and ghcr.io, and the robot
# Woodpecker pushes with. Product projects are declared by ../fabricata.nix.
{
  ref,
  relic,
  ...
}: let
  cache = registry: {
    name = "${registry}_cache";
    registry_id = ref.harbor_registry.${registry}.registry_id;
    public = true;
    vulnerability_scanning = true;
    auto_sbom_generation = true;
  };
in {
  reliquary.woodpecker_secrets.generator = "tofunix-harbor-woodpecker-secret";

  resource.harbor_registry = {
    docker = {
      provider_name = "docker-hub";
      name = "docker_cache";
      endpoint_url = "https://hub.docker.com";
    };
    ghcr = {
      provider_name = "github";
      name = "github_cache";
      endpoint_url = "https://ghcr.io";
    };
  };

  resource.harbor_project = {
    docker_cache = cache "docker";
    ghcr_cache = cache "ghcr";
  };

  scriptorium.robots.woodpecker = {
    description = "Robot account for Woodpecker CI";
    secret = relic "woodpecker_secrets" "woodpecker_password";
  };
}
