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
    base_uri = "https://forge.${domain}";
    api_token = "\${data.sops_file.forgejo_secrets.data[\"forgejo_token\"]}";
  };

  resource.forgejo_organization.monolith-softworks = {
    name = "monolith-softworks";
    full_name = "Monolith Softworks";
  };

  resource.forgejo_repository.zellij = {
    name = "zellij";
    description = "Zellij wrapper flake";
    private = false;
    default_branch = "master";
    has_pull_requests = true;
    has_actions = true;
    has_issues = true;
  };

  # Push mirror example - uncomment and configure when ready:
  resource.forgejo_repository_push_mirror.zellij-github = {
    owner = "manjo";
    repository = "zellij";
    remote_address = "https://github.com/apetrovic6/zellij";
    sync_on_commit = true;
    use_ssh = true;
  };

  resource.forgejo_repository_push_mirror.zellij-codeberg = {
    owner = "manjo";
    repository = "zellij";
    remote_address = "https://codeberg.org/apetrovic/zellij";
    sync_on_commit = true;
    use_ssh = true;
  };
}
