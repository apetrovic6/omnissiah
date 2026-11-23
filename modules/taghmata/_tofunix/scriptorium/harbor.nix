# Harbor: the pull-through caches for Docker Hub and ghcr.io. Product projects
# and their CI robots are declared by ../fabricata.nix.
{
  ref,
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
}
