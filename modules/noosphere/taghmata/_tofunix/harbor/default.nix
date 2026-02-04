{ref, ...}: let
  secretsFile = toString ../../../../../vars/shared/tofunix-harbor-secrets/tofunix-harbor-secrets/value;
in {
  data.sops_file.secrets = {
    source_file = secretsFile;
    input_type = "yaml";
  };

  provider.harbor.default = {
    url = "https://harbor.noosphere.uk";
    username = "\${data.sops_file.secrets.data[\"harbor_username\"]}";
    password = "\${data.sops_file.secrets.data[\"harbor_password\"]}";
  };

  resource.harbor_project.docker_cache = {
    name = "docker_cache";
    registry_id = ref.harbor_registry.docker.registry_id;
    public = true;
    vulnerability_scanning = true;
    auto_sbom_generation = true;
  };

  resource.harbor_registry.docker = {
    provider_name = "docker-hub";
    name = "docker_cache";
    endpoint_url = "https://hub.docker.com";
  };

  resource.harbor_project.ghcr_cache = {
    name = "ghcr_cache";
    registry_id = ref.harbor_registry.ghcr.registry_id;
    public = true;
    vulnerability_scanning = true;
    auto_sbom_generation = true;
  };

  resource.harbor_registry.ghcr = {
    provider_name = "github";
    name = "github_cache";
    endpoint_url = "https://ghcr.io";
  };
}
