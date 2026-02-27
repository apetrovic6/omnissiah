{ref, ...}: let
  secretsFile = toString ../../../../../vars/shared/tofunix-forgejo-nix-secret/tofunix-forgejo-nix-secret/value;
in {
  data.sops_file.forgejo_nix_secrets = {
    source_file = secretsFile;
    input_type = "yaml";
  };

  provider.forgejo.cerberus = {
    base_uri = "https://forge.ugalabugala.org";
    api_token = "\${data.sops_file.forgejo_nix_secrets.data[\"forgejo_token\"]}";
  };
}
