{ref, ...}: let
  secretsFile = toString ../../../../../vars/shared/tofunix-forgejo-secret/tofunix-forgejo-secret/value;
  noosphere = import ../../../../vars/_noosphere-values.nix;
  inherit (noosphere) domain;
in {
  data.sops_file.forgejo_secrets = {
    source_file = secretsFile;
    input_type = "yaml";
  };

  provider.forgejo.default = {
    alias = "manjo";
    host = "https://forgejo.${domain}";
    api_token = "\${data.sops_file.forgejo_secrets.data[\"forgejo_token\"]}";
  };

  resource.forgejo_organization.monolith-sotfworks = {
    provider = ref.forgejo.username;
    name = "Monolith Softworks";
  };

  # Add your forgejo resources here, e.g.:
  # resource.forgejo_organization.example = {
  #   name = "my-org";
  # };
}
